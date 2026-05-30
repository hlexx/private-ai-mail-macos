import Foundation
import GRDB
import MailDomain
import Persistence

public enum SendQueueServiceError: Error, Equatable, Sendable {
    case noRecipients
    case invalidQueuedItem(String)
    case providerUnavailable(MailProviderIdentifier)
}

public enum SendQueueCredentialStatus: Equatable, Sendable {
    case authorized
    case offline
    case missingCredential
    case insufficientScope
    case authExpired
}

public struct SendQueueCredentialAuthorization: Equatable, Sendable {
    public let status: SendQueueCredentialStatus
    public let providerErrorCode: String?
    public let userVisibleMessage: String?
    public let retryAfterSeconds: Int?

    public init(
        status: SendQueueCredentialStatus,
        providerErrorCode: String? = nil,
        userVisibleMessage: String? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.status = status
        self.providerErrorCode = providerErrorCode
        self.userVisibleMessage = userVisibleMessage
        self.retryAfterSeconds = retryAfterSeconds
    }

    public static let authorized = SendQueueCredentialAuthorization(status: .authorized)
}

public protocol SendQueueCredentialAuthorizing: Sendable {
    func authorization(for item: QueuedOutgoingMessage) async -> SendQueueCredentialAuthorization
}

public struct AllowingSendQueueCredentialAuthorizer: SendQueueCredentialAuthorizing {
    public init() {}

    public func authorization(for item: QueuedOutgoingMessage) async -> SendQueueCredentialAuthorization {
        .authorized
    }
}

public enum SendQueueExecutionOutcome: Equatable, Sendable {
    case noEligibleItem
    case retryScheduled(QueuedOutgoingMessage)
    case needsConsent(QueuedOutgoingMessage)
    case failed(QueuedOutgoingMessage)
    case sent(QueuedOutgoingMessage)
}

public actor SendQueueService {
    private let storage: DatabaseSendQueueStorage
    private let providers: [MailProviderIdentifier: any MailSendProvider]
    private let credentialAuthorizer: any SendQueueCredentialAuthorizing
    private let sentReconciler: LocalSentMessageReconciler
    private let now: @Sendable () -> Date

    public init(
        db: AppDatabase,
        providers: [any MailSendProvider],
        credentialAuthorizer: any SendQueueCredentialAuthorizing = AllowingSendQueueCredentialAuthorizer(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.storage = DatabaseSendQueueStorage(db: db)
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.provider, $0) })
        self.credentialAuthorizer = credentialAuthorizer
        self.sentReconciler = LocalSentMessageReconciler(db: db)
        self.now = now
    }

    public func enqueueDraft(
        _ draft: DraftMessage,
        id: SendQueueItemID = .generate(),
        idempotencyKey: SendIdempotencyKey = .generate()
    ) async throws -> QueuedOutgoingMessage {
        guard !draft.to.isEmpty else {
            throw SendQueueServiceError.noRecipients
        }

        let currentTime = now()
        try await storage.saveDraft(draft)
        let queued = QueuedOutgoingMessage(
            id: id,
            draftID: draft.id,
            provider: draft.provider,
            accountID: draft.accountID,
            idempotencyKey: idempotencyKey,
            status: .pending,
            from: draft.from,
            to: draft.to,
            cc: draft.cc,
            bcc: draft.bcc,
            subject: draft.subject,
            bodyText: draft.bodyText,
            bodyHTML: draft.bodyHTML,
            bodyStorage: draft.bodyStorage,
            threadID: draft.threadID,
            replyToProviderMessageID: draft.replyToProviderMessageID,
            rfcMessageID: draft.rfcMessageID,
            rfcInReplyTo: draft.rfcInReplyTo,
            rfcReferences: draft.rfcReferences,
            createdAt: currentTime,
            updatedAt: currentTime
        )
        return try await enqueue(queued)
    }

    public func enqueue(_ message: QueuedOutgoingMessage) async throws -> QueuedOutgoingMessage {
        guard !message.to.isEmpty else {
            throw SendQueueServiceError.noRecipients
        }
        return try await storage.enqueue(message)
    }

    public func fetchQueuedMessage(id: SendQueueItemID) async throws -> QueuedOutgoingMessage? {
        try await storage.fetch(id: id)
    }

    public func cancel(id: SendQueueItemID) async throws -> QueuedOutgoingMessage? {
        guard let item = try await storage.fetch(id: id) else {
            return nil
        }
        switch item.status {
        case .pending, .retryScheduled, .needsConsent:
            return try await storage.save(
                item.updating(
                    status: .canceled,
                    nextAttemptAt: nil,
                    updatedAt: now(),
                    sanitizedFailure: nil
                )
            )
        case .sending, .sent, .failed, .canceled, .duplicateSuppressed:
            return item
        }
    }

    public func executeNextEligible() async throws -> SendQueueExecutionOutcome {
        guard let item = try await storage.fetchNextEligible(now: now()) else {
            return .noEligibleItem
        }

        let authorization = await credentialAuthorizer.authorization(for: item)
        if authorization.status != .authorized {
            return try await applyPreflightFailure(authorization, to: item)
        }

        guard let provider = providers[item.provider] else {
            let failure = SanitizedSendFailure(
                category: .unsupportedOperation,
                providerErrorCode: "send_provider_unavailable",
                occurredAt: now()
            )
            let failed = try await storage.save(
                item.updating(
                    status: .failed,
                    updatedAt: now(),
                    sanitizedFailure: failure
                )
            )
            return .failed(failed)
        }

        let attemptStartedAt = now()
        let leased = try await storage.save(
            item.updating(
                status: .sending,
                nextAttemptAt: nil,
                lastAttemptAt: attemptStartedAt,
                updatedAt: attemptStartedAt,
                sanitizedFailure: nil
            )
        )

        do {
            let result = try await provider.send(ProviderSendRequest(queuedMessage: leased))
            do {
                _ = try await sentReconciler.reconcileQueuedSend(item: leased, result: result)
            } catch {
                let failure = SanitizedSendFailure(
                    category: .ambiguousCompletion,
                    providerErrorCode: "local_sent_reconcile_failed",
                    occurredAt: now()
                )
                let failed = try await storage.save(
                    leased.updating(
                        status: .failed,
                        providerMessageID: result.providerMessageID,
                        providerThreadID: result.providerThreadID,
                        rfcMessageID: result.rfcMessageID ?? leased.rfcMessageID,
                        attempts: leased.attempts + 1,
                        updatedAt: now(),
                        sanitizedFailure: failure
                    )
                )
                return .failed(failed)
            }

            let sent = try await storage.save(
                leased.updating(
                    status: .sent,
                    providerMessageID: result.providerMessageID,
                    providerThreadID: result.providerThreadID,
                    rfcMessageID: result.rfcMessageID ?? leased.rfcMessageID,
                    attempts: leased.attempts + 1,
                    updatedAt: result.sentAt,
                    sentAt: result.sentAt,
                    sanitizedFailure: nil
                )
            )
            return .sent(sent)
        } catch {
            let failure: SanitizedSendFailure
            if let providerError = error as? ProviderSendError {
                failure = providerError.failure
            } else {
                failure = SanitizedSendFailure(
                    category: .unknown,
                    providerErrorCode: "send_provider_unknown",
                    occurredAt: now()
                )
            }
            return try await applyProviderFailure(failure, to: leased)
        }
    }

    private func applyPreflightFailure(
        _ authorization: SendQueueCredentialAuthorization,
        to item: QueuedOutgoingMessage
    ) async throws -> SendQueueExecutionOutcome {
        let currentTime = now()
        let failure = SanitizedSendFailure(
            category: authorization.status.failureCategory,
            providerErrorCode: authorization.providerErrorCode ?? authorization.status.defaultProviderErrorCode,
            userVisibleMessage: authorization.userVisibleMessage,
            retryAfterSeconds: authorization.retryAfterSeconds,
            occurredAt: currentTime
        )

        switch authorization.status {
        case .authorized:
            return .noEligibleItem
        case .offline:
            let retryAt = retryDate(
                for: item,
                attemptsCompleted: item.attempts,
                failure: failure,
                now: currentTime
            )
            let updated = try await storage.save(
                item.updating(
                    status: .retryScheduled,
                    nextAttemptAt: retryAt,
                    updatedAt: currentTime,
                    sanitizedFailure: failure
                )
            )
            return .retryScheduled(updated)
        case .missingCredential, .insufficientScope, .authExpired:
            let updated = try await storage.save(
                item.updating(
                    status: .needsConsent,
                    nextAttemptAt: nil,
                    updatedAt: currentTime,
                    sanitizedFailure: failure
                )
            )
            return .needsConsent(updated)
        }
    }

    private func applyProviderFailure(
        _ failure: SanitizedSendFailure,
        to item: QueuedOutgoingMessage
    ) async throws -> SendQueueExecutionOutcome {
        let attempts = item.attempts + 1
        let currentTime = now()

        if failure.category.requiresConsent {
            let updated = try await storage.save(
                item.updating(
                    status: .needsConsent,
                    attempts: attempts,
                    nextAttemptAt: nil,
                    lastAttemptAt: currentTime,
                    updatedAt: currentTime,
                    sanitizedFailure: failure
                )
            )
            return .needsConsent(updated)
        }

        if failure.category.isAutoRetryable,
           item.retryPolicy.canRetry(afterAttempts: attempts),
           let retryAt = retryDate(
            for: item,
            attemptsCompleted: attempts,
            failure: failure,
            now: currentTime
           ) {
            let updated = try await storage.save(
                item.updating(
                    status: .retryScheduled,
                    attempts: attempts,
                    nextAttemptAt: retryAt,
                    lastAttemptAt: currentTime,
                    updatedAt: currentTime,
                    sanitizedFailure: failure
                )
            )
            return .retryScheduled(updated)
        }

        let updated = try await storage.save(
            item.updating(
                status: .failed,
                attempts: attempts,
                nextAttemptAt: nil,
                lastAttemptAt: currentTime,
                updatedAt: currentTime,
                sanitizedFailure: failure
            )
        )
        return .failed(updated)
    }

    private func retryDate(
        for item: QueuedOutgoingMessage,
        attemptsCompleted: Int,
        failure: SanitizedSendFailure,
        now currentTime: Date
    ) -> Date? {
        if let retryAfterSeconds = failure.retryAfterSeconds {
            return currentTime.addingTimeInterval(TimeInterval(retryAfterSeconds))
        }
        guard let delay = item.retryPolicy.delaySeconds(forNextAttemptAfter: attemptsCompleted) else {
            return nil
        }
        return currentTime.addingTimeInterval(TimeInterval(delay))
    }
}

private struct DatabaseSendQueueStorage: Sendable {
    let db: AppDatabase

    func saveDraft(_ draft: DraftMessage) async throws {
        let record = try Self.record(from: draft)
        try await db.write { database in
            try record.save(database)
        }
    }

    func enqueue(_ message: QueuedOutgoingMessage) async throws -> QueuedOutgoingMessage {
        if let existing = try await fetch(
            provider: message.provider,
            accountID: message.accountID,
            idempotencyKey: message.idempotencyKey
        ) {
            return existing
        }

        do {
            return try await save(message)
        } catch {
            if let existing = try await fetch(
                provider: message.provider,
                accountID: message.accountID,
                idempotencyKey: message.idempotencyKey
            ) {
                return existing
            }
            throw error
        }
    }

    func fetch(id: SendQueueItemID) async throws -> QueuedOutgoingMessage? {
        try db.read { database in
            try SendQueueItemRecord.fetchOne(database, key: id.rawValue).map(Self.message(from:))
        }
    }

    func fetch(
        provider: MailProviderIdentifier,
        accountID: String,
        idempotencyKey: SendIdempotencyKey
    ) async throws -> QueuedOutgoingMessage? {
        try db.read { database in
            try SendQueueItemRecord
                .filter(Column("provider") == provider.rawValue)
                .filter(Column("account_id") == accountID)
                .filter(Column("idempotency_key") == idempotencyKey.rawValue)
                .fetchOne(database)
                .map(Self.message(from:))
        }
    }

    func fetchNextEligible(now: Date) async throws -> QueuedOutgoingMessage? {
        let nowUnix = Int(now.timeIntervalSince1970)
        return try db.read { database in
            try SendQueueItemRecord.fetchOne(
                database,
                sql: """
                SELECT *
                FROM send_queue_item
                WHERE status = ?
                   OR (status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?))
                ORDER BY created_at ASC
                LIMIT 1
                """,
                arguments: [
                    SendQueueStatus.pending.rawValue,
                    SendQueueStatus.retryScheduled.rawValue,
                    nowUnix,
                ]
            ).map(Self.message(from:))
        }
    }

    func save(_ message: QueuedOutgoingMessage) async throws -> QueuedOutgoingMessage {
        let record = try Self.record(from: message)
        try await db.write { database in
            try record.save(database)
        }
        return message
    }

    private static func message(from record: SendQueueItemRecord) throws -> QueuedOutgoingMessage {
        guard let status = SendQueueStatus(rawValue: record.status) else {
            throw SendQueueServiceError.invalidQueuedItem("Unknown queue status: \(record.status)")
        }
        guard let bodyStorage = DraftBodyStorage(rawValue: record.bodyStorage) else {
            throw SendQueueServiceError.invalidQueuedItem("Unknown body storage: \(record.bodyStorage)")
        }
        let failure = try sanitizedFailure(from: record)

        return QueuedOutgoingMessage(
            id: SendQueueItemID(rawValue: record.id),
            draftID: record.draftId.map(DraftID.init(rawValue:)),
            provider: MailProviderIdentifier(rawValue: record.provider),
            accountID: record.accountId,
            idempotencyKey: SendIdempotencyKey(rawValue: record.idempotencyKey),
            status: status,
            from: parseAddress(record.fromAddr),
            to: parseAddressList(record.toAddr),
            cc: parseAddressList(record.ccAddr),
            bcc: parseAddressList(record.bccAddr),
            subject: record.subject,
            bodyText: record.bodyText,
            bodyHTML: record.bodyHtml,
            bodyStorage: bodyStorage,
            threadID: record.threadId,
            replyToProviderMessageID: record.replyToProviderMessageId,
            providerMessageID: record.providerMessageId,
            providerThreadID: record.providerThreadId,
            rfcMessageID: record.rfcMessageId,
            rfcInReplyTo: record.rfcInReplyTo,
            rfcReferences: try decodeStringArray(record.rfcReferencesJson),
            attempts: record.attempts,
            retryPolicy: SendRetryPolicy(
                backoffSeconds: SendRetryPolicy.trustMVPDefault.backoffSeconds,
                maxProviderAttempts: record.maxAttempts
            ),
            nextAttemptAt: record.nextAttemptAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            lastAttemptAt: record.lastAttemptAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            createdAt: Date(timeIntervalSince1970: TimeInterval(record.createdAt)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(record.updatedAt)),
            sentAt: record.sentAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            sanitizedFailure: failure
        )
    }

    private static func record(from message: QueuedOutgoingMessage) throws -> SendQueueItemRecord {
        SendQueueItemRecord(
            id: message.id.rawValue,
            draftId: message.draftID?.rawValue,
            accountId: message.accountID,
            provider: message.provider.rawValue,
            idempotencyKey: message.idempotencyKey.rawValue,
            status: message.status.rawValue,
            fromAddr: formatAddress(message.from),
            toAddr: formatAddressList(message.to),
            ccAddr: message.cc.isEmpty ? nil : formatAddressList(message.cc),
            bccAddr: message.bcc.isEmpty ? nil : formatAddressList(message.bcc),
            subject: message.subject,
            bodyText: message.bodyText,
            bodyHtml: message.bodyHTML,
            bodyStorage: message.bodyStorage.rawValue,
            threadId: message.threadID,
            replyToProviderMessageId: message.replyToProviderMessageID,
            providerMessageId: message.providerMessageID,
            providerThreadId: message.providerThreadID,
            rfcMessageId: message.rfcMessageID,
            rfcInReplyTo: message.rfcInReplyTo,
            rfcReferencesJson: try encodeStringArray(message.rfcReferences),
            attempts: message.attempts,
            maxAttempts: message.retryPolicy.maxProviderAttempts,
            nextAttemptAt: message.nextAttemptAt.map { Int($0.timeIntervalSince1970) },
            lastAttemptAt: message.lastAttemptAt.map { Int($0.timeIntervalSince1970) },
            createdAt: Int(message.createdAt.timeIntervalSince1970),
            updatedAt: Int(message.updatedAt.timeIntervalSince1970),
            sentAt: message.sentAt.map { Int($0.timeIntervalSince1970) },
            sanitizedErrorCategory: message.sanitizedFailure?.category.rawValue,
            sanitizedErrorCode: message.sanitizedFailure?.providerErrorCode,
            sanitizedErrorMessage: message.sanitizedFailure?.userVisibleMessage,
            retryAfterSeconds: message.sanitizedFailure?.retryAfterSeconds
        )
    }

    private static func record(from draft: DraftMessage) throws -> DraftRecord {
        DraftRecord(
            id: draft.id.rawValue,
            accountId: draft.accountID,
            provider: draft.provider.rawValue,
            fromAddr: formatAddress(draft.from),
            toAddr: formatAddressList(draft.to),
            ccAddr: draft.cc.isEmpty ? nil : formatAddressList(draft.cc),
            bccAddr: draft.bcc.isEmpty ? nil : formatAddressList(draft.bcc),
            subject: draft.subject,
            bodyText: draft.bodyText,
            bodyHtml: draft.bodyHTML,
            bodyStorage: draft.bodyStorage.rawValue,
            threadId: draft.threadID,
            replyToProviderMessageId: draft.replyToProviderMessageID,
            rfcMessageId: draft.rfcMessageID,
            rfcInReplyTo: draft.rfcInReplyTo,
            rfcReferencesJson: try encodeStringArray(draft.rfcReferences),
            createdAt: Int(draft.createdAt.timeIntervalSince1970),
            updatedAt: Int(draft.updatedAt.timeIntervalSince1970)
        )
    }

    private static func sanitizedFailure(from record: SendQueueItemRecord) throws -> SanitizedSendFailure? {
        guard let categoryRaw = record.sanitizedErrorCategory else {
            return nil
        }
        guard let category = SendFailureCategory(rawValue: categoryRaw) else {
            throw SendQueueServiceError.invalidQueuedItem("Unknown send failure category: \(categoryRaw)")
        }
        return SanitizedSendFailure(
            category: category,
            providerErrorCode: record.sanitizedErrorCode,
            userVisibleMessage: record.sanitizedErrorMessage,
            retryAfterSeconds: record.retryAfterSeconds,
            occurredAt: record.lastAttemptAt
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ?? Date(timeIntervalSince1970: TimeInterval(record.updatedAt))
        )
    }

    private static func parseAddress(_ raw: String) -> Address {
        Address(rfc822: raw) ?? Address(email: raw)
    }

    private static func parseAddressList(_ raw: String?) -> [Address] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(Address.init(rfc822:))
    }

    private static func formatAddress(_ address: Address) -> String {
        if let name = address.name {
            return "\(name) <\(address.email)>"
        }
        return address.email
    }

    private static func formatAddressList(_ addresses: [Address]) -> String {
        addresses.map(formatAddress).joined(separator: ", ")
    }

    private static func decodeStringArray(_ raw: String) throws -> [String] {
        guard let data = raw.data(using: .utf8) else {
            throw SendQueueServiceError.invalidQueuedItem("Invalid UTF-8 references JSON")
        }
        return try JSONDecoder().decode([String].self, from: data)
    }

    private static func encodeStringArray(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SendQueueServiceError.invalidQueuedItem("Invalid encoded references JSON")
        }
        return string
    }
}

private extension SendQueueCredentialStatus {
    var failureCategory: SendFailureCategory {
        switch self {
        case .authorized:
            return .unknown
        case .offline:
            return .offline
        case .missingCredential:
            return .missingCredential
        case .insufficientScope:
            return .insufficientScope
        case .authExpired:
            return .authExpired
        }
    }

    var defaultProviderErrorCode: String {
        switch self {
        case .authorized:
            return "authorized"
        case .offline:
            return "offline"
        case .missingCredential:
            return "missing_credential"
        case .insufficientScope:
            return "insufficient_scope"
        case .authExpired:
            return "auth_expired"
        }
    }
}

private extension SendFailureCategory {
    var requiresConsent: Bool {
        switch self {
        case .missingCredential, .insufficientScope, .authExpired:
            return true
        case .offline, .timeout, .rateLimited, .providerUnavailable, .validation,
             .notFound, .invalidResponse, .unsupportedOperation, .conflict,
             .ambiguousCompletion, .unknown:
            return false
        }
    }

    var isAutoRetryable: Bool {
        switch self {
        case .offline, .timeout, .rateLimited, .providerUnavailable:
            return true
        case .missingCredential, .insufficientScope, .authExpired, .validation,
             .notFound, .invalidResponse, .unsupportedOperation, .conflict,
             .ambiguousCompletion, .unknown:
            return false
        }
    }
}

private extension QueuedOutgoingMessage {
    func updating(
        status: SendQueueStatus,
        providerMessageID: String? = nil,
        providerThreadID: String? = nil,
        rfcMessageID: String? = nil,
        attempts: Int? = nil,
        nextAttemptAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        updatedAt: Date,
        sentAt: Date? = nil,
        sanitizedFailure: SanitizedSendFailure?
    ) -> QueuedOutgoingMessage {
        QueuedOutgoingMessage(
            id: id,
            draftID: draftID,
            provider: provider,
            accountID: accountID,
            idempotencyKey: idempotencyKey,
            status: status,
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            bodyText: bodyText,
            bodyHTML: bodyHTML,
            bodyStorage: bodyStorage,
            threadID: threadID,
            replyToProviderMessageID: replyToProviderMessageID,
            providerMessageID: providerMessageID ?? self.providerMessageID,
            providerThreadID: providerThreadID ?? self.providerThreadID,
            rfcMessageID: rfcMessageID ?? self.rfcMessageID,
            rfcInReplyTo: rfcInReplyTo,
            rfcReferences: rfcReferences,
            attempts: attempts ?? self.attempts,
            retryPolicy: retryPolicy,
            nextAttemptAt: nextAttemptAt,
            lastAttemptAt: lastAttemptAt ?? self.lastAttemptAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sentAt: sentAt ?? self.sentAt,
            sanitizedFailure: sanitizedFailure
        )
    }
}
