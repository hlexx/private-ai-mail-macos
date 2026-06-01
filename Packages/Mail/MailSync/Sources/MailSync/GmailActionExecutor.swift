import Foundation
import IntegrationDomain
import MailDomain
import MailProviders
import Persistence

public struct GmailActionExecutor: ActionExecuting {
    private let mutator: MailMutator
    private let apiFactory: GmailAPIFactory
    private let now: @Sendable () -> Date

    public init(
        db: AppDatabase,
        apiFactory: @escaping GmailAPIFactory,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.mutator = MailMutator(db: db, apiFactory: apiFactory)
        self.apiFactory = apiFactory
        self.now = now
    }

    public init(
        mutator: MailMutator,
        apiFactory: @escaping GmailAPIFactory,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.mutator = mutator
        self.apiFactory = apiFactory
        self.now = now
    }

    public func execute(command: ActionCommand) async -> ActionResult {
        guard command.kind.isTrustMVPLocalAction else {
            return failureResult(command: command, failureKind: .validationFailed, providerCategory: nil)
        }

        do {
            switch command.kind {
            case .draftReply:
                return try await createDraft(command: command)
            case .archiveThread:
                let threadId = try threadId(from: command)
                try await mutator.archive(threadId, accountId: command.accountId)
                return successResult(command: command, operation: "archiveThread", externalResultId: externalThreadId(threadId))
            case .starThread:
                let threadId = try threadId(from: command)
                try await mutator.star(threadId, accountId: command.accountId)
                return successResult(command: command, operation: "starThread", externalResultId: externalThreadId(threadId))
            case .markRead:
                let threadId = try threadId(from: command)
                try await mutator.markRead(threadId, accountId: command.accountId, read: true)
                return successResult(command: command, operation: "markRead", externalResultId: externalThreadId(threadId))
            case .trashThread:
                let threadId = try threadId(from: command)
                try await mutator.trash(threadId, accountId: command.accountId)
                return successResult(command: command, operation: "trashThread", externalResultId: externalThreadId(threadId))
            case .sendReply, .snoozeThread, .sendToSlack, .createNotionPage, .logToCRM:
                return failureResult(command: command, failureKind: .validationFailed, providerCategory: nil)
            }
        } catch let error as GmailActionExecutorError {
            return failureResult(command: command, failureKind: error.failureKind, providerCategory: nil)
        } catch let error as MailMutationError {
            return failureResult(
                command: command,
                failureKind: Self.failureKind(for: error.category),
                providerCategory: error.category
            )
        } catch let error as GmailAPIError {
            let category = error.sharedCategory
            return failureResult(
                command: command,
                failureKind: Self.failureKind(for: category),
                providerCategory: category
            )
        } catch {
            return failureResult(command: command, failureKind: .unknown, providerCategory: nil)
        }
    }

    private func createDraft(command: ActionCommand) async throws -> ActionResult {
        let request = try draftRequest(from: command)
        let raw = try MIMEBuilder.encode(
            OutgoingMessage(
                from: request.from,
                to: request.to,
                cc: request.cc,
                bcc: request.bcc,
                subject: request.subject,
                body: request.bodyForPlainTextProvider,
                inReplyTo: request.rfcInReplyTo,
                references: request.rfcReferences,
                messageIDSeed: command.idempotencyKey.rawValue,
                messageIDHeader: request.rfcMessageID
            )
        )
        let draft = try await apiFactory(command.accountId).createDraft(
            raw: raw,
            threadId: request.threadID
        )
        return successResult(
            command: command,
            operation: "draftReply",
            externalResultId: "gmail:draft:\(draft.id)",
            extraMetadata: [
                "hasDraftId": .bool(true),
                "hasProviderMessageId": .bool(!draft.message.id.isEmpty),
                "recipientCount": .int(request.to.count),
            ]
        )
    }

    private func draftRequest(from command: ActionCommand) throws -> GmailDraftActionPayload {
        let data = try JSONEncoder().encode(command.payload.body)
        let request = try JSONDecoder().decode(GmailDraftActionPayload.self, from: data)
        guard request.accountID == command.accountId else {
            throw GmailActionExecutorError.validationFailed
        }
        guard request.from.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              request.to.isEmpty == false else {
            throw GmailActionExecutorError.validationFailed
        }
        let targetThreadId = try threadId(from: command)
        guard request.threadID == nil || request.threadID == targetThreadId else {
            throw GmailActionExecutorError.validationFailed
        }
        return request.withThreadID(targetThreadId)
    }

    private func threadId(from command: ActionCommand) throws -> String {
        switch command.target {
        case .thread(_, let threadId), .message(_, let threadId, _):
            return threadId
        case .attachment, .integrationDestination:
            throw GmailActionExecutorError.validationFailed
        }
    }

    private func successResult(
        command: ActionCommand,
        operation: String,
        externalResultId: String,
        extraMetadata: [String: JSONValue] = [:]
    ) -> ActionResult {
        ActionResult(
            status: .succeeded,
            externalResultId: externalResultId,
            completedAt: now(),
            metadata: metadata(
                command: command,
                operation: operation,
                result: "accepted",
                providerCategory: nil,
                extra: extraMetadata
            )
        )
    }

    private func failureResult(
        command: ActionCommand,
        failureKind: ActionFailureKind,
        providerCategory: MailProviderErrorCategory?
    ) -> ActionResult {
        ActionResult(
            status: .failed,
            failureKind: failureKind,
            metadata: metadata(
                command: command,
                operation: command.kind.rawValue,
                result: "failed",
                providerCategory: providerCategory,
                extra: ["failureKind": .string(failureKind.rawValue)]
            )
        )
    }

    private func metadata(
        command: ActionCommand,
        operation: String,
        result: String,
        providerCategory: MailProviderErrorCategory?,
        extra: [String: JSONValue]
    ) -> JSONValue {
        var fields: [String: JSONValue] = [
            "actionKind": .string(command.kind.rawValue),
            "executor": .string("gmail"),
            "operation": .string(operation),
            "provider": .string("gmail"),
            "result": .string(result),
            "targetKind": .string(command.target.kind.rawValue),
        ]
        if let providerCategory {
            fields["providerErrorCategory"] = .string(providerCategory.rawValue)
        }
        fields.merge(extra) { _, new in new }
        return .object(fields)
    }

    private func externalThreadId(_ threadId: String) -> String {
        "gmail:thread:\(threadId)"
    }

    private static func failureKind(for category: MailProviderErrorCategory) -> ActionFailureKind {
        switch category {
        case .missingCredential, .authExpired:
            return .authenticationRequired
        case .insufficientScope:
            return .permissionDenied
        case .rateLimited:
            return .rateLimited
        case .offline:
            return .networkUnavailable
        case .providerUnavailable:
            return .executionFailed
        case .notFound, .invalidResponse, .unsupportedOperation, .conflict:
            return .providerRejected
        }
    }
}

public struct GmailDraftActionPayload: Codable, Equatable, Sendable {
    public let accountID: String
    public let from: Address
    public let to: [Address]
    public let cc: [Address]
    public let bcc: [Address]
    public let subject: String
    public let bodyText: String?
    public let bodyHTML: String?
    public let threadID: String?
    public let rfcMessageID: String?
    public let rfcInReplyTo: String?
    public let rfcReferences: [String]

    public init(
        accountID: String,
        from: Address,
        to: [Address],
        cc: [Address] = [],
        bcc: [Address] = [],
        subject: String,
        bodyText: String? = nil,
        bodyHTML: String? = nil,
        threadID: String? = nil,
        rfcMessageID: String? = nil,
        rfcInReplyTo: String? = nil,
        rfcReferences: [String] = []
    ) {
        self.accountID = accountID
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.threadID = threadID
        self.rfcMessageID = rfcMessageID
        self.rfcInReplyTo = rfcInReplyTo
        self.rfcReferences = rfcReferences
    }

    var bodyForPlainTextProvider: String {
        bodyText ?? bodyHTML ?? ""
    }

    func withThreadID(_ threadID: String) -> GmailDraftActionPayload {
        GmailDraftActionPayload(
            accountID: accountID,
            from: from,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            bodyText: bodyText,
            bodyHTML: bodyHTML,
            threadID: threadID,
            rfcMessageID: rfcMessageID,
            rfcInReplyTo: rfcInReplyTo,
            rfcReferences: rfcReferences
        )
    }
}

private enum GmailActionExecutorError: Error {
    case validationFailed

    var failureKind: ActionFailureKind {
        switch self {
        case .validationFailed:
            return .validationFailed
        }
    }
}
