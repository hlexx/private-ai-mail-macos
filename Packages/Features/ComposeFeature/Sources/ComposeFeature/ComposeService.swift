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

        let outgoing = OutgoingMessage(
            from: draft.from,
            to: draft.to,
            cc: draft.cc,
            bcc: draft.bcc,
            subject: draft.subject,
            body: draft.body,
            inReplyTo: draft.replyContext?.inReplyToMessageID,
            references: draft.replyContext?.referencesChain ?? []
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
        let sentAtUnix = Int(now.timeIntervalSince1970)

        let record = MessageRecord(
            id: sent.id,
            threadId: sent.threadId,
            accountId: draft.accountID,
            fromAddr: formatAddr(draft.from),
            toAddr: formatAddrList(draft.to),
            ccAddr: draft.cc.isEmpty ? nil : formatAddrList(draft.cc),
            sentAt: sentAtUnix,
            snippet: String(draft.body.prefix(200)),
            bodyText: draft.body,
            flags: MessageRecord.sentByMe | MessageRecord.read
        )

        let subject = draft.subject
        let isNewThread = draft.replyContext == nil
        let threadId = sent.threadId
        let accountID = draft.accountID

        try await Self.insertSentRecord(
            record: record,
            isNewThread: isNewThread,
            threadId: threadId,
            accountID: accountID,
            subject: subject,
            sentAtUnix: sentAtUnix,
            db: db
        )

        return SentEcho(messageID: sent.id, threadID: sent.threadId, sentAt: now)
    }

    @DatabaseActor
    private static func insertSentRecord(
        record: MessageRecord,
        isNewThread: Bool,
        threadId: String,
        accountID: String,
        subject: String,
        sentAtUnix: Int,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            try record.save(dbConn, onConflict: .replace)

            if isNewThread {
                let thread = ThreadRecord(
                    id: threadId,
                    accountId: accountID,
                    subject: subject,
                    lastMessageAt: sentAtUnix,
                    messageCount: 1
                )
                try thread.save(dbConn, onConflict: .replace)
            }
        }
    }

    private func formatAddr(_ addr: Address) -> String {
        if let name = addr.name {
            return "\(name) <\(addr.email)>"
        }
        return addr.email
    }

    private func formatAddrList(_ addrs: [Address]) -> String {
        addrs.map { formatAddr($0) }.joined(separator: ", ")
    }
}
