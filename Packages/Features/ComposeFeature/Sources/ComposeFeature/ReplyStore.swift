import AIKit
import Foundation
import GRDB
import Observation
import os
import Persistence

@Observable
@MainActor
public final class ReplyStore {
    public internal(set) var reply: AIThreadReply?
    public private(set) var isLoading = false
    public private(set) var error: (any Error)?
    public private(set) var focusRequestCount: Int = 0

    private let aiService: (any AIService)?
    private let db: AppDatabase?
    private var replyCache: [CacheKey: AIThreadReply] = [:]
    private var inflightTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: "com.hlexx.privateaimail",
        category: "ReplyStore"
    )

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

    public static func preview(error: any Error) -> ReplyStore {
        let store = ReplyStore()
        store.error = error
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
            if Self.isDisplayableDraft(cached.body) {
                reply = cached
                isLoading = false
                return
            }
            replyCache.removeValue(forKey: key)
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
                guard Self.isDisplayableDraft(aiReply.body) else {
                    throw AIError.invalidStructuredOutput("draft body was placeholder")
                }

                replyCache[key] = aiReply
                reply = aiReply
                isLoading = false
                error = nil
                Self.logger.info(
                    "Draft reply generated account=\(key.accountId, privacy: .public) thread=\(key.threadID, privacy: .public) tone=\(tone.rawValue, privacy: .public)"
                )
            } catch is CancellationError {
                // Don't update state
            } catch {
                self.error = error
                isLoading = false
                reply = nil
                Self.logger.error(
                    "Draft reply failed account=\(key.accountId, privacy: .public) thread=\(key.threadID, privacy: .public) category=\(Self.errorCategory(error), privacy: .public)"
                )
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
        if let cached = replyCache[key] {
            if Self.isDisplayableDraft(cached.body) {
                reply = cached
                focusRequestCount += 1
                return
            }
            replyCache.removeValue(forKey: key)
        }
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

    private nonisolated static func errorCategory(_ error: any Error) -> String {
        if let aiError = error as? AIError {
            switch aiError {
            case .modelNotInstalled:
                return "modelNotInstalled"
            case .modelLoadFailed:
                return "modelLoadFailed"
            case .inferenceFailed:
                return "inferenceFailed"
            case .invalidStructuredOutput:
                return "invalidStructuredOutput"
            case .cancelled:
                return "cancelled"
            }
        }
        return String(describing: type(of: error))
    }

    nonisolated static func isDisplayableDraft(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }

        let blockedValues: Set<String> = [
            "...",
            "…",
            "type",
            "string",
            "body",
            "placeholder",
            "example",
            "todo",
            "n/a",
        ]
        return !blockedValues.contains(trimmed.lowercased())
    }
}

// MARK: - Cache Key

private struct CacheKey: Hashable {
    let threadID: String
    let accountId: String
    let tone: AIReplyTone
    let replyLanguage: String
}
