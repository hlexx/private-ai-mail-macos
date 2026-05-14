import AIKit
import Foundation
import GRDB
import Observation
import Persistence

@Observable
@MainActor
public final class BriefStore {
    public internal(set) var brief: ThreadBriefViewData?
    public private(set) var activeThreadID: String?
    public private(set) var isLoading = false
    public private(set) var error: (any Error)?

    private let aiService: (any AIService)?
    private let db: AppDatabase?
    private var briefCache: [String: CacheEntry] = [:]
    private var inflightTask: Task<Void, Never>?

    /// Production init with AI service and database.
    public init(aiService: any AIService, db: AppDatabase) {
        self.aiService = aiService
        self.db = db
    }

    /// Preview / snapshot-test init with stub behaviour.
    public init() {
        self.aiService = nil
        self.db = nil
    }

    /// Create a preview store pre-populated with a brief.
    public static func preview(brief: ThreadBriefViewData?) -> BriefStore {
        let store = BriefStore()
        store.brief = brief
        return store
    }

    public func loadBrief(forThreadID threadID: String?) {
        inflightTask?.cancel()
        inflightTask = nil
        activeThreadID = threadID
        error = nil

        guard let threadID else {
            brief = nil
            isLoading = false
            return
        }

        guard let aiService, let db else {
            brief = nil
            isLoading = false
            return
        }

        isLoading = true
        brief = nil

        inflightTask = Task {
            do {
                let input = try fetchThreadInput(threadID: threadID, db: db)
                let latestMessageKey = input.messages.last.map { "\($0.from)-\($0.sentAt)" } ?? ""

                // Check cache with message-key freshness
                if let cached = briefCache[threadID], cached.latestMessageKey == latestMessageKey {
                    brief = cached.viewData
                    isLoading = false
                    return
                }

                try Task.checkCancellation()
                let aiBrief = try await aiService.threadBrief(input)
                try Task.checkCancellation()

                let viewData = ThreadBriefViewData(from: aiBrief)
                briefCache[threadID] = CacheEntry(viewData: viewData, latestMessageKey: latestMessageKey)
                brief = viewData
                isLoading = false
                error = nil
            } catch is CancellationError {
                // Cancelled — don't update state
            } catch let err as AIError where err.isCancelled {
                // AI-level cancellation
            } catch {
                if activeThreadID == threadID {
                    self.error = error
                    isLoading = false
                    brief = nil
                }
            }
        }
    }

    public func retry() {
        let id = activeThreadID
        activeThreadID = nil
        loadBrief(forThreadID: id)
    }

    // MARK: - Private

    private func fetchThreadInput(threadID: String, db: AppDatabase) throws -> AIThreadInput {
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
                bodyText: msg.bodyText ?? msg.snippet ?? ""
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

// MARK: - Cache

private struct CacheEntry {
    let viewData: ThreadBriefViewData
    let latestMessageKey: String
}

// MARK: - ThreadBriefViewData convenience

extension ThreadBriefViewData {
    init(from brief: AIThreadBrief) {
        self.init(
            summary: brief.summary ?? "No summary available",
            request: brief.request,
            deadline: brief.deadline,
            risk: brief.risk,
            nextStep: brief.nextStep,
            confidence: brief.confidence,
            evidence: brief.evidence
        )
    }
}

// MARK: - AIError helper

private extension AIError {
    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
