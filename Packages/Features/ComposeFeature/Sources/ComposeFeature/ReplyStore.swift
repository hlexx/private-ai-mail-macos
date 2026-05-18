import AIKit
import Foundation
import GRDB
import Observation
import Persistence

@Observable
@MainActor
public final class ReplyStore {
    public internal(set) var reply: AIThreadReply?
    public private(set) var isLoading = false
    public private(set) var error: (any Error)?

    private let aiService: (any AIService)?
    private let db: AppDatabase?
    private var replyCache: [CacheKey: AIThreadReply] = [:]
    private var inflightTask: Task<Void, Never>?

    public init(aiService: any AIService, db: AppDatabase) {
        self.aiService = aiService
        self.db = db
    }

    /// Preview init.
    public init() {
        self.aiService = nil
        self.db = nil
    }

    public static func preview(reply: AIThreadReply?) -> ReplyStore {
        let store = ReplyStore()
        store.reply = reply
        return store
    }

    public func generate(
        threadID: String,
        accountId: String? = nil,
        tone: AIReplyTone,
        replyLanguage: String?,
        locale: Locale = .current
    ) {
        inflightTask?.cancel()
        error = nil

        guard let aiService, let db else {
            reply = nil
            isLoading = false
            return
        }

        let key = CacheKey(threadID: threadID, accountId: accountId ?? "", tone: tone, replyLanguage: replyLanguage ?? "")
        if let cached = replyCache[key] {
            reply = cached
            isLoading = false
            return
        }

        isLoading = true
        reply = nil

        inflightTask = Task {
            do {
                let input = try await Task.detached {
                    try self.fetchThreadInput(threadID: threadID, accountId: accountId, db: db)
                }.value

                try Task.checkCancellation()
                let aiReply = try await aiService.draftReply(
                    input,
                    tone: tone,
                    locale: locale,
                    replyLanguage: replyLanguage
                )
                try Task.checkCancellation()

                replyCache[key] = aiReply
                reply = aiReply
                isLoading = false
                error = nil
            } catch is CancellationError {
                // Don't update state
            } catch {
                self.error = error
                isLoading = false
                reply = nil
            }
        }
    }

    public func regenerate(
        threadID: String,
        accountId: String? = nil,
        tone: AIReplyTone,
        replyLanguage: String?,
        locale: Locale = .current
    ) {
        let key = CacheKey(threadID: threadID, accountId: accountId ?? "", tone: tone, replyLanguage: replyLanguage ?? "")
        replyCache.removeValue(forKey: key)
        generate(threadID: threadID, accountId: accountId, tone: tone, replyLanguage: replyLanguage, locale: locale)
    }

    public func generateIfNeeded(
        threadID: String,
        accountId: String? = nil,
        tone: AIReplyTone,
        replyLanguage: String?,
        locale: Locale = .current
    ) {
        let key = CacheKey(threadID: threadID, accountId: accountId ?? "", tone: tone, replyLanguage: replyLanguage ?? "")
        if replyCache[key] != nil { return }
        generate(threadID: threadID, accountId: accountId, tone: tone, replyLanguage: replyLanguage, locale: locale)
    }

    public func invalidate(threadID: String) {
        replyCache = replyCache.filter { $0.key.threadID != threadID }
        reply = nil
    }

    // MARK: - Private

    private nonisolated func fetchThreadInput(threadID: String, accountId: String?, db: AppDatabase) throws -> AIThreadInput {
        let (messages, attachments) = try db.read { database in
            let msgs: [MessageRecord]
            if let accountId {
                msgs = try MessageRecord
                    .filter(Column("thread_id") == threadID && Column("account_id") == accountId)
                    .order(Column("sent_at").asc)
                    .fetchAll(database)
            } else {
                msgs = try MessageRecord
                    .filter(Column("thread_id") == threadID)
                    .order(Column("sent_at").asc)
                    .fetchAll(database)
            }
            let msgIDs = msgs.map(\.id)
            let atts: [AttachmentRecord]
            if msgIDs.isEmpty {
                atts = []
            } else if let accountId {
                atts = try AttachmentRecord
                    .filter(msgIDs.contains(Column("message_id")) && Column("account_id") == accountId)
                    .fetchAll(database)
            } else {
                atts = try AttachmentRecord
                    .filter(msgIDs.contains(Column("message_id")))
                    .fetchAll(database)
            }
            return (msgs, atts)
        }

        let aiMessages = messages.map { msg in
            AIThreadInput.Message(
                from: msg.fromAddr ?? "Unknown",
                sentAt: Date(timeIntervalSince1970: TimeInterval(msg.sentAt)),
                bodyText: msg.bestPlainText
            )
        }
        let aiAttachments = attachments.map { att in
            AIThreadInput.Attachment(
                filename: att.filename ?? "unnamed",
                mime: att.mime ?? "application/octet-stream"
            )
        }
        return AIThreadInput(messages: aiMessages, attachments: aiAttachments)
    }

}

// MARK: - Cache Key

private struct CacheKey: Hashable {
    let threadID: String
    let accountId: String
    let tone: AIReplyTone
    let replyLanguage: String
}
