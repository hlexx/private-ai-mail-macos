import Foundation
import GRDB
import MailDomain
import MailProviders
import Persistence

// MARK: - DTOs

public struct ComposeDraft: Sendable {
    public let accountID: String
    public let from: Address
    public let to: [Address]
    public let cc: [Address]
    public let bcc: [Address]
    public let subject: String
    public let body: String
    public let replyContext: ReplyContext?

    public init(
        accountID: String,
        from: Address,
        to: [Address],
        cc: [Address] = [],
        bcc: [Address] = [],
        subject: String,
        body: String,
        replyContext: ReplyContext? = nil
    ) {
        self.accountID = accountID
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.replyContext = replyContext
    }
}

public struct ReplyContext: Sendable {
    public let threadID: String
    public let inReplyToMessageID: String
    public let referencesChain: [String]

    public init(threadID: String, inReplyToMessageID: String, referencesChain: [String] = []) {
        self.threadID = threadID
        self.inReplyToMessageID = inReplyToMessageID
        self.referencesChain = referencesChain
    }
}

public struct SentEcho: Sendable {
    public let messageID: String
    public let threadID: String
    public let sentAt: Date

    public init(messageID: String, threadID: String, sentAt: Date) {
        self.messageID = messageID
        self.threadID = threadID
        self.sentAt = sentAt
    }
}

// MARK: - Errors

public enum ComposeError: Error, Sendable {
    case noRecipients
    case noAccount
    case needsReconsent
    case send(underlying: any Error & Sendable)
}

// MARK: - Protocol

public protocol ComposeService: Sendable {
    func send(_ draft: ComposeDraft) async throws -> SentEcho
}

// MARK: - Live Implementation

public final class LiveComposeService: ComposeService, Sendable {
    private let api: any GmailAPI
    private let db: AppDatabase

    public init(api: any GmailAPI, db: AppDatabase) {
        self.api = api
        self.db = db
    }

    public func send(_ draft: ComposeDraft) async throws -> SentEcho {
        guard !draft.to.isEmpty else {
            throw ComposeError.noRecipients
        }

        let messageIDSeed = UUID().uuidString.lowercased()
        let outgoing = OutgoingMessage(
            from: draft.from,
            to: draft.to,
            cc: draft.cc,
            bcc: draft.bcc,
            subject: draft.subject,
            body: draft.body,
            inReplyTo: draft.replyContext?.inReplyToMessageID,
            references: draft.replyContext?.referencesChain ?? [],
            messageIDSeed: messageIDSeed
        )

        let raw: String
        do {
            raw = try MIMEBuilder.encode(outgoing)
        } catch {
            throw ComposeError.send(underlying: error)
        }

        let sent: GmailDTO.SentMessage
        do {
            sent = try await api.sendMessage(raw: raw, threadId: draft.replyContext?.threadID)
        } catch let error as GmailAPIError {
            if case .insufficientScope = error {
                throw ComposeError.needsReconsent
            }
            throw ComposeError.send(underlying: error)
        } catch {
            throw ComposeError.send(underlying: error)
        }

        let now = Date()
        let generatedMessageId = "<\(messageIDSeed)@hlexx.privateaimail>"

        return try await LocalSentMessageReconciler(db: db).reconcileGmailDirectSend(
            draft: draft,
            sent: sent,
            rfcMessageID: generatedMessageId,
            sentAt: now
        )
    }
}
