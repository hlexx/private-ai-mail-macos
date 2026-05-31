import AppFoundation
import Foundation
import MailDomain
import MailProviders
import Observation

// MARK: - Send State

public enum ComposeSendState: Sendable {
    case idle
    case awaitingApproval(deadline: Date)
    case pending
    case sending
    case retrying
    case needsReconsent
    case sent
    case failed(ComposeError)

    public var key: String {
        switch self {
        case .idle: return "idle"
        case .awaitingApproval: return "awaiting"
        case .pending: return "pending"
        case .sending: return "sending"
        case .retrying: return "retrying"
        case .needsReconsent: return "needsReconsent"
        case .sent: return "sent"
        case .failed: return "failed"
        }
    }

    var allowsNewSendRequest: Bool {
        if case .idle = self {
            return true
        }
        return false
    }
}

// MARK: - Send Queue Boundary

public protocol ComposeSendQueueProcessing: Sendable {
    func enqueueDraft(
        _ draft: DraftMessage,
        id: SendQueueItemID,
        idempotencyKey: SendIdempotencyKey
    ) async throws -> QueuedOutgoingMessage
    func retry(id: SendQueueItemID) async throws -> QueuedOutgoingMessage?
    func cancel(id: SendQueueItemID) async throws -> QueuedOutgoingMessage?
    func execute(id: SendQueueItemID) async throws -> SendQueueExecutionOutcome
}

extension SendQueueService: ComposeSendQueueProcessing {}

private struct ComposeQueueUnavailableError: Error, Sendable {}

private struct ComposeSanitizedQueueFailure: Error, Sendable {
    let failure: SanitizedSendFailure
}

extension ComposeError {
    var userActionableFailure: UserActionableFailure {
        switch self {
        case .noRecipients:
            return UserActionableFailure(category: .unknown, operation: .send)
        case .noAccount:
            return UserActionableFailure(category: .missingCredential, operation: .send)
        case .needsReconsent:
            return UserActionableFailure(category: .insufficientScope, operation: .send)
        case .send(let underlying):
            if let queuedFailure = underlying as? ComposeSanitizedQueueFailure {
                return queuedFailure.failure.userActionableFailure()
            }
            if let providerSendError = underlying as? ProviderSendError {
                return providerSendError.failure.userActionableFailure()
            }
            if let gmailError = underlying as? GmailAPIError {
                return gmailError.userActionableFailure(operation: .send)
            }
            if let graphError = underlying as? GraphAPIError {
                return graphError.userActionableFailure(operation: .send)
            }
            return UserActionableFailure.coerce(underlying, operation: .send)
        }
    }
}

private struct DirectComposeSendQueueProcessor: ComposeSendQueueProcessing {
    let service: any ComposeService

    func enqueueDraft(
        _ draft: DraftMessage,
        id: SendQueueItemID,
        idempotencyKey: SendIdempotencyKey
    ) async throws -> QueuedOutgoingMessage {
        let now = Date()
        return QueuedOutgoingMessage(
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
            createdAt: now,
            updatedAt: now
        )
    }

    func retry(id: SendQueueItemID) async throws -> QueuedOutgoingMessage? {
        nil
    }

    func cancel(id: SendQueueItemID) async throws -> QueuedOutgoingMessage? {
        nil
    }

    func execute(id: SendQueueItemID) async throws -> SendQueueExecutionOutcome {
        throw ComposeQueueUnavailableError()
    }

    func sendDirect(_ draft: ComposeDraft) async throws -> SentEcho {
        try await service.send(draft)
    }
}

// MARK: - ComposeViewModel

@Observable
@MainActor
public final class ComposeViewModel {

    public var toField: String = ""
    public var ccField: String = ""
    public var subjectField: String = ""
    public var bodyText: String = ""
    public var sendState: ComposeSendState = .idle

    public var selectedAccountID: String?
    public var selectedAccountEmail: String?
    public var accounts: [AccountInfo] = []

    public var replyContext: ReplyContext?

    public var recipientCount: Int {
        parseAddresses(toField).count + parseAddresses(ccField).count
    }

    private var countdownTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private let sendQueueFactory: @Sendable (String) throws -> any ComposeSendQueueProcessing
    private let directComposeServiceFactory: (@Sendable (String) throws -> any ComposeService)?
    private let reauthorizeHandler: @Sendable (String) async throws -> Void
    private var activeQueueItemID: SendQueueItemID?
    private var activeIdempotencyKey: SendIdempotencyKey?

    public init(
        composeServiceFactory: @escaping @Sendable (String) throws -> any ComposeService,
        reauthorizeHandler: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.sendQueueFactory = { accountID in
            DirectComposeSendQueueProcessor(service: try composeServiceFactory(accountID))
        }
        self.directComposeServiceFactory = composeServiceFactory
        self.reauthorizeHandler = reauthorizeHandler
    }

    public init(
        sendQueueFactory: @escaping @Sendable (String) throws -> any ComposeSendQueueProcessing,
        reauthorizeHandler: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.sendQueueFactory = sendQueueFactory
        self.directComposeServiceFactory = nil
        self.reauthorizeHandler = reauthorizeHandler
    }

    // MARK: - Reset

    public func reset() {
        cancelSend()
        toField = ""
        ccField = ""
        subjectField = ""
        bodyText = ""
        replyContext = nil
        activeQueueItemID = nil
        activeIdempotencyKey = nil
    }

    // MARK: - Reply Pre-fill

    public func prefillReply(
        fromAddr: String,
        subject: String,
        threadID: String,
        lastMessageID: String,
        referencesChain: [String] = []
    ) {
        toField = fromAddr
        subjectField = Self.deduplicateRePrefix(subject)
        replyContext = ReplyContext(
            threadID: threadID,
            inReplyToMessageID: lastMessageID,
            referencesChain: referencesChain
        )
    }

    // MARK: - Reply All Pre-fill

    public func prefillReplyAll(
        fromAddr: String,
        allToAddrs: String,
        allCcAddrs: String,
        subject: String,
        threadID: String,
        lastMessageID: String,
        referencesChain: [String] = []
    ) {
        toField = [fromAddr, allToAddrs]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        ccField = allCcAddrs
        subjectField = Self.deduplicateRePrefix(subject)
        replyContext = ReplyContext(
            threadID: threadID,
            inReplyToMessageID: lastMessageID,
            referencesChain: referencesChain
        )
    }

    // MARK: - Forward Pre-fill

    public func prefillForward(
        subject: String,
        quotedBody: String,
        threadID: String,
        lastMessageID: String,
        referencesChain: [String] = []
    ) {
        toField = ""
        subjectField = Self.deduplicateForwardPrefix(subject)
        bodyText = quotedBody
        replyContext = ReplyContext(
            threadID: threadID,
            inReplyToMessageID: lastMessageID,
            referencesChain: referencesChain
        )
    }

    // MARK: - Send Flow

    public func requestSend() {
        guard canRequestSend else { return }
        let deadline = Date().addingTimeInterval(5)
        sendState = .awaitingApproval(deadline: deadline)
        countdownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.executeSend()
        }
    }

    public func cancelSend() {
        countdownTask?.cancel()
        countdownTask = nil
        sendTask?.cancel()
        sendTask = nil
        let queueID = activeQueueItemID
        activeQueueItemID = nil
        activeIdempotencyKey = nil
        if let queueID, let accountID = selectedAccountID {
            Task { [sendQueueFactory] in
                guard let queue = try? sendQueueFactory(accountID) else { return }
                _ = try? await queue.cancel(id: queueID)
            }
        }
        sendState = .idle
    }

    public func confirmSendNow() {
        guard case .awaitingApproval = sendState else { return }
        countdownTask?.cancel()
        countdownTask = nil
        executeSend()
    }

    public func retrySend() {
        countdownTask?.cancel()
        countdownTask = nil
        sendTask?.cancel()
        sendTask = nil
        guard let accountID = selectedAccountID,
              let queueID = activeQueueItemID else {
            sendState = .idle
            requestSend()
            return
        }
        sendState = .pending
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let queue = try self.sendQueueFactory(accountID)
                _ = try await queue.retry(id: queueID)
                guard !Task.isCancelled else { return }
                self.sendState = .sending
                let outcome = try await queue.execute(id: queueID)
                guard !Task.isCancelled else { return }
                self.applyQueueOutcome(outcome)
            } catch {
                guard !Task.isCancelled else { return }
                self.sendState = self.composeErrorState(for: error)
            }
        }
    }

    public func reauthorizeAndRetry() {
        let canReauthorize: Bool = {
            if case .needsReconsent = sendState {
                return true
            }
            if case .failed(.needsReconsent) = sendState {
                return true
            }
            return false
        }()
        guard canReauthorize else { return }
        guard let accountID = selectedAccountID else { return }
        sendState = .sending
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.reauthorizeHandler(accountID)
                guard !Task.isCancelled else { return }
                self.retrySend()
            } catch {
                guard !Task.isCancelled else { return }
                self.sendState = .failed(.send(underlying: error))
            }
        }
    }

    public var canRequestSend: Bool {
        sendState.allowsNewSendRequest
            && !toField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Private

    private func executeSend() {
        guard let accountID = selectedAccountID,
              let accountEmail = selectedAccountEmail else {
            sendState = .failed(.noAccount)
            return
        }

        sendState = .pending

        sendTask = Task { [weak self] in
            guard let self else { return }

            do {
                if let directFactory = self.directComposeServiceFactory {
                    try await self.executeDirectSend(
                        accountID: accountID,
                        accountEmail: accountEmail,
                        serviceFactory: directFactory
                    )
                    return
                }

                let draft = self.makeDraftMessage(accountID: accountID, accountEmail: accountEmail)
                let queue = try self.sendQueueFactory(accountID)
                let queueID = self.activeQueueItemID ?? .generate()
                let idempotencyKey = self.activeIdempotencyKey ?? .generate()
                self.activeQueueItemID = queueID
                self.activeIdempotencyKey = idempotencyKey

                let queued = try await queue.enqueueDraft(
                    draft,
                    id: queueID,
                    idempotencyKey: idempotencyKey
                )
                guard !Task.isCancelled else { return }
                self.activeQueueItemID = queued.id
                self.sendState = .sending
                let outcome = try await queue.execute(id: queued.id)
                guard !Task.isCancelled else { return }
                self.applyQueueOutcome(outcome)
            } catch let error as ComposeError {
                guard !Task.isCancelled else { return }
                self.sendState = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                self.sendState = self.composeErrorState(for: error)
            }
        }
    }

    private func executeDirectSend(
        accountID: String,
        accountEmail: String,
        serviceFactory: @Sendable (String) throws -> any ComposeService
    ) async throws {
        sendState = .sending
        let draft = makeComposeDraft(accountID: accountID, accountEmail: accountEmail)
        let service = try serviceFactory(accountID)
        _ = try await service.send(draft)
        guard !Task.isCancelled else { return }
        sendState = .sent
    }

    private func makeComposeDraft(accountID: String, accountEmail: String) -> ComposeDraft {
        let displayName = accounts.first(where: { $0.id == accountID })?.displayName
        return ComposeDraft(
            accountID: accountID,
            from: Address(name: displayName, email: accountEmail),
            to: parseAddresses(toField),
            cc: parseAddresses(ccField),
            subject: subjectField,
            body: bodyText,
            replyContext: replyContext
        )
    }

    private func makeDraftMessage(accountID: String, accountEmail: String) -> DraftMessage {
        let composeDraft = makeComposeDraft(accountID: accountID, accountEmail: accountEmail)
        let now = Date()
        let account = accounts.first(where: { $0.id == accountID })
        return DraftMessage(
            id: DraftID.generate(),
            provider: account?.provider ?? .gmail,
            accountID: accountID,
            from: composeDraft.from,
            to: composeDraft.to,
            cc: composeDraft.cc,
            bcc: composeDraft.bcc,
            subject: composeDraft.subject,
            bodyText: composeDraft.body,
            bodyHTML: nil,
            bodyStorage: .sqlite,
            threadID: composeDraft.replyContext?.threadID,
            replyToProviderMessageID: nil,
            rfcMessageID: nil,
            rfcInReplyTo: composeDraft.replyContext?.inReplyToMessageID,
            rfcReferences: composeDraft.replyContext?.referencesChain ?? [],
            createdAt: now,
            updatedAt: now
        )
    }

    private func applyQueueOutcome(_ outcome: SendQueueExecutionOutcome) {
        switch outcome {
        case .noEligibleItem:
            sendState = .failed(.send(underlying: ComposeQueueUnavailableError()))
        case .retryScheduled(let item):
            activeQueueItemID = item.id
            sendState = .retrying
        case .needsConsent(let item):
            activeQueueItemID = item.id
            sendState = .needsReconsent
        case .failed(let item):
            activeQueueItemID = item.id
            if let failure = item.sanitizedFailure {
                sendState = .failed(.send(underlying: ComposeSanitizedQueueFailure(failure: failure)))
            } else {
                sendState = .failed(.send(underlying: ComposeQueueUnavailableError()))
            }
        case .sent(let item):
            activeQueueItemID = item.id
            sendState = .sent
        }
    }

    private func composeErrorState(for error: any Error) -> ComposeSendState {
        if let sendQueueError = error as? SendQueueServiceError,
           case .noRecipients = sendQueueError {
            return .failed(.noRecipients)
        }
        return .failed(.send(underlying: error))
    }

    private func parseAddresses(_ raw: String) -> [Address] {
        splitAddresses(raw)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { chunk -> Address in
                if let open = chunk.firstIndex(of: "<"),
                   let close = chunk.firstIndex(of: ">") {
                    let email = String(chunk[chunk.index(after: open)..<close])
                    let name = chunk[chunk.startIndex..<open].trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanName = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return Address(name: cleanName.isEmpty ? nil : cleanName, email: email)
                }
                return Address(name: nil, email: chunk)
            }
    }

    /// Split on commas, respecting quoted strings and angle brackets.
    private func splitAddresses(_ raw: String) -> [String] {
        var results: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false

        for ch in raw {
            if ch == "\"" && !inAngle {
                inQuotes.toggle()
                current.append(ch)
            } else if ch == "<" && !inQuotes {
                inAngle = true
                current.append(ch)
            } else if ch == ">" && !inQuotes {
                inAngle = false
                current.append(ch)
            } else if ch == "," && !inQuotes && !inAngle {
                results.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            results.append(current)
        }
        return results
    }

    public nonisolated static func deduplicateRePrefix(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("re: ") {
            return trimmed
        }
        return "Re: \(trimmed)"
    }

    public nonisolated static func deduplicateForwardPrefix(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("fwd: ") {
            return trimmed
        }
        return "Fwd: \(trimmed)"
    }
}

// MARK: - Account Info

public struct AccountInfo: Identifiable, Sendable {
    public let id: String
    public let email: String
    public let displayName: String?
    public let provider: MailProviderIdentifier

    public init(
        id: String,
        email: String,
        displayName: String? = nil,
        provider: MailProviderIdentifier = .gmail
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.provider = provider
    }
}
