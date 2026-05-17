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

        let key = CacheKey(threadID: threadID, tone: tone, replyLanguage: replyLanguage ?? "")
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
                    try self.fetchThreadInput(threadID: threadID, db: db)
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
        tone: AIReplyTone,
        replyLanguage: String?,
        locale: Locale = .current
    ) {
        let key = CacheKey(threadID: threadID, tone: tone, replyLanguage: replyLanguage ?? "")
        replyCache.removeValue(forKey: key)
        generate(threadID: threadID, tone: tone, replyLanguage: replyLanguage, locale: locale)
    }

    public func invalidate(threadID: String) {
        replyCache = replyCache.filter { $0.key.threadID != threadID }
        reply = nil
    }

    // MARK: - Private

    private nonisolated func fetchThreadInput(threadID: String, db: AppDatabase) throws -> AIThreadInput {
        let (messages, attachments) = try db.read { database in
            let msgs = try MessageRecord
                .filter(Column("thread_id") == threadID)
                .order(Column("sent_at").asc)
                .fetchAll(database)
            let msgIDs = msgs.map(\.id)
            let atts: [AttachmentRecord]
            if msgIDs.isEmpty {
                atts = []
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
                bodyText: Self.bestPlainText(msg)
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

    private static nonisolated func bestPlainText(_ msg: MessageRecord) -> String {
        if let text = msg.bodyText, !text.isEmpty { return text }
        if let html = msg.bodyHtml, !html.isEmpty {
            return htmlToPlainText(html) ?? msg.snippet ?? ""
        }
        return msg.snippet ?? ""
    }

    /// Convert HTML to plain text by stripping tags. Thread-safe (no WebKit dependency).
    private static nonisolated func htmlToPlainText(_ html: String) -> String? {
        var text = html
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

// MARK: - Cache Key

private struct CacheKey: Hashable {
    let threadID: String
    let tone: AIReplyTone
    let replyLanguage: String
}
