import ActionsFeature
import Foundation
import GRDB
import IntegrationDomain
import MailDomain
import MailSync
import Persistence

@MainActor
final class ActionQueueService: TrustActionQueueing {
    private let db: AppDatabase
    private let executionStore: ActionOutboxExecutionStore
    private let now: @Sendable () -> Date

    init(
        db: AppDatabase,
        executionStore: ActionOutboxExecutionStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.db = db
        self.executionStore = executionStore
        self.now = now
    }

    func start(_ request: TrustActionRequest) async -> TrustActionQueueOutcome {
        do {
            try await enqueue(request)
            let result = try await executionStore.execute(opId: request.requestId)
            return Self.outcome(opId: request.requestId, result: result)
        } catch {
            return TrustActionQueueOutcome(
                opId: request.requestId,
                status: .failedNonRetryable,
                failureKind: .validationFailed,
                message: TrustActionFailureCopy.message(for: .validationFailed)
            )
        }
    }

    func retry(opId: String) async -> TrustActionQueueOutcome? {
        do {
            _ = try await executionStore.recoverStaleExecuting(opId: opId)
            guard try await prepareRetry(opId: opId) else { return nil }
            let result = try await executionStore.execute(opId: opId)
            return Self.outcome(opId: opId, result: result)
        } catch {
            return TrustActionQueueOutcome(
                opId: opId,
                status: .failedRetryable,
                failureKind: .unknown,
                message: TrustActionFailureCopy.message(for: .unknown)
            )
        }
    }

    private func enqueue(_ request: TrustActionRequest) async throws {
        let timestamp = timestampValue(now())
        let command = try await command(for: request, timestamp: timestamp)
        let payloadJSON = try encodeJSONString(command.payload)
        try await db.write { database in
            if try ActionOutboxRecord.fetchOne(database, key: request.requestId) != nil {
                return
            }
            try ActionOutboxRecord(
                opId: command.opId,
                accountId: command.accountId,
                targetKind: command.target.kind.rawValue,
                threadId: request.target.threadId,
                actionKind: command.kind.rawValue,
                sensitivity: command.sensitivity.rawValue,
                actionSchemaVersion: command.schemaVersion,
                idempotencyKey: command.idempotencyKey.rawValue,
                approvalRequirement: command.approvalRequirement.rawValue,
                approvalState: command.approvalState.rawValue,
                status: command.status.rawValue,
                payloadJSON: payloadJSON,
                attemptCount: command.attemptCount,
                createdAt: timestamp,
                updatedAt: timestamp,
                approvedAt: timestamp
            ).insert(database)
        }
    }

    private func prepareRetry(opId: String) async throws -> Bool {
        let timestamp = timestampValue(now())
        return try await db.write { database in
            guard var record = try ActionOutboxRecord.fetchOne(database, key: opId),
                  record.status == ActionStatus.failed.rawValue,
                  TrustActionFailureCopy.isRetryable(record.lastErrorKind.flatMap(ActionFailureKind.init(rawValue:))) else {
                return false
            }
            record.status = ActionStatus.ready.rawValue
            record.approvalState = ApprovalState.approved.rawValue
            record.updatedAt = timestamp
            try record.update(database)
            return true
        }
    }

}

extension ActionQueueService {

    func recentOutboxItems(limit: Int = 5) async -> [TrustActionOutboxItem] {
        (try? db.read { database in
            let records = try ActionOutboxRecord.fetchAll(
                database,
                sql: """
                    SELECT * FROM action_outbox
                    ORDER BY updated_at DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            return try records.compactMap { record in
                try Self.outboxItem(from: record, database: database)
            }
        }) ?? []
    }

    nonisolated private static func outboxItem(
        from record: ActionOutboxRecord,
        database: Database
    ) throws -> TrustActionOutboxItem? {
        guard let action = TrustMVPAction(rawValue: record.actionKind),
              let threadId = record.threadId else {
            return nil
        }
        let subject = try String.fetchOne(
            database,
            sql: "SELECT subject FROM thread WHERE account_id = ? AND id = ?",
            arguments: [record.accountId, threadId]
        ) ?? ""
        let failureKind = record.lastErrorKind.flatMap(ActionFailureKind.init(rawValue:))
        return TrustActionOutboxItem(
            id: record.opId,
            action: action,
            target: TrustActionTarget(
                accountId: record.accountId,
                threadId: threadId,
                subject: subject
            ),
            status: displayStatus(record.status, failureKind: failureKind),
            failureKind: failureKind,
            message: message(record.status, failureKind: failureKind)
        )
    }
}

extension ActionQueueService {

    private func command(
        for request: TrustActionRequest,
        timestamp: Int,
        status: ActionStatus = .ready
    ) async throws -> ActionCommand {
        try ActionCommand(
            opId: request.requestId,
            accountId: request.target.accountId,
            target: .thread(accountId: request.target.accountId, threadId: request.target.threadId),
            kind: request.action.kind,
            sensitivity: request.action == .trashThread ? .sensitive : .standard,
            payload: try await payload(for: request),
            userActionId: request.requestId,
            approvalRequirement: request.action.requiresExplicitConfirmation ? .explicitConfirm : .notRequired,
            approvalState: request.action.requiresExplicitConfirmation ? .approved : .notRequired,
            status: status,
            createdAt: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(timestamp))
        )
    }

    private func payload(for request: TrustActionRequest) async throws -> ActionPayload {
        guard try await isSupportedGmailAccount(request.target.accountId) else {
            throw ActionQueueServiceError.unsupportedProvider
        }
        guard request.action == .draftReply else {
            return ActionPayload(body: .object([
                "source": .string("user"),
                "surface": .string("trustMVP"),
            ]))
        }

        let draftPayload = try await draftPayload(for: request)
        return try ActionPayload(encoding: draftPayload)
    }

    private func isSupportedGmailAccount(_ accountId: String) async throws -> Bool {
        try db.read { database in
            try AccountRecord.fetchOne(database, key: accountId)?.provider == "gmail"
        }
    }

    private func draftPayload(for request: TrustActionRequest) async throws -> GmailDraftActionPayload {
        try db.read { database in
            guard let account = try AccountRecord.fetchOne(database, key: request.target.accountId) else {
                throw ActionQueueServiceError.invalidDraftPayload
            }
            let messages = try MessageRecord
                .filter(
                    Column("account_id") == request.target.accountId
                        && Column("thread_id") == request.target.threadId
                )
                .order(Column("sent_at"))
                .fetchAll(database)
            guard let replyTarget = messages.last(where: { $0.flags & MessageRecord.sentByMe == 0 }) ?? messages.last,
                  let recipient = Self.replyRecipient(from: replyTarget) else {
                throw ActionQueueServiceError.invalidDraftPayload
            }

            return GmailDraftActionPayload(
                accountID: account.id,
                from: Address(name: account.displayName, email: account.email),
                to: [recipient],
                subject: Self.replySubject(request.target.subject),
                bodyText: "",
                threadID: request.target.threadId,
                rfcInReplyTo: replyTarget.messageIdHeader ?? replyTarget.id,
                rfcReferences: messages.compactMap(\.messageIdHeader)
            )
        }
    }

    nonisolated private static func replyRecipient(from message: MessageRecord) -> Address? {
        if let from = message.fromAddr, let address = Address(rfc822: from) {
            return address
        }
        if let to = message.toAddr, let address = Address(rfc822: to) {
            return address
        }
        return nil
    }

    nonisolated private static func replySubject(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let prefix = trimmed.range(of: "re:", options: [.anchored, .caseInsensitive])
        return prefix == nil ? "Re: \(trimmed)" : trimmed
    }

    private func encodeJSONString(_ value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ActionQueueServiceError.invalidJSONEncoding
        }
        return json
    }

    private func timestampValue(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970)
    }
}

extension ActionQueueService {

    nonisolated private static func outcome(opId: String, result: ActionResult) -> TrustActionQueueOutcome {
        switch result.status {
        case .succeeded:
            return TrustActionQueueOutcome(
                opId: opId,
                status: .completed,
                message: "Action completed"
            )
        case .failed:
            let retryable = TrustActionFailureCopy.isRetryable(result.failureKind)
            return TrustActionQueueOutcome(
                opId: opId,
                status: retryable ? .failedRetryable : .failedNonRetryable,
                failureKind: result.failureKind,
                message: TrustActionFailureCopy.message(for: result.failureKind)
            )
        case .pending:
            return TrustActionQueueOutcome(opId: opId, status: .pending, message: "Queued action")
        case .ready, .executing:
            return TrustActionQueueOutcome(opId: opId, status: .running, message: "Running action")
        case .cancelled, .blocked:
            return TrustActionQueueOutcome(
                opId: opId,
                status: .failedNonRetryable,
                failureKind: .cancelled,
                message: TrustActionFailureCopy.message(for: .cancelled)
            )
        }
    }

    nonisolated private static func displayStatus(
        _ rawStatus: String,
        failureKind: ActionFailureKind?
    ) -> TrustActionDisplayStatus {
        switch ActionStatus(rawValue: rawStatus) {
        case .pending:
            return .pending
        case .ready, .executing:
            return .running
        case .succeeded:
            return .completed
        case .failed:
            return TrustActionFailureCopy.isRetryable(failureKind) ? .failedRetryable : .failedNonRetryable
        case .blocked, .cancelled, nil:
            return .failedNonRetryable
        }
    }

    nonisolated private static func message(_ rawStatus: String, failureKind: ActionFailureKind?) -> String {
        switch ActionStatus(rawValue: rawStatus) {
        case .pending:
            return "Queued action"
        case .ready, .executing:
            return "Running action"
        case .succeeded:
            return "Action completed"
        case .failed:
            return TrustActionFailureCopy.message(for: failureKind)
        case .blocked, .cancelled, nil:
            return TrustActionFailureCopy.message(for: .cancelled)
        }
    }
}

private enum ActionQueueServiceError: Error {
    case invalidJSONEncoding
    case invalidDraftPayload
    case unsupportedProvider
}
