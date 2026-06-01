import AIKit
import AppFoundation
import Foundation
import GRDB
import NaturalLanguage
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
    private var briefCache: [BriefCacheKey: CacheEntry] = [:]
    private var inflightTask: Task<Void, Never>?
    private var activeAccountId: String?

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

    public func loadBrief(forThreadID threadID: String?, accountId: String? = nil) {
        inflightTask?.cancel()
        inflightTask = nil
        activeThreadID = threadID
        activeAccountId = accountId
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

        let cacheKey = BriefCacheKey(threadID: threadID, accountId: accountId ?? "")

        inflightTask = Task {
            do {
                let fetchResult = try await Task.detached {
                    try Self.fetchThreadData(threadID: threadID, accountId: accountId, db: db)
                }.value

                let resolvedAccountId = fetchResult.resolvedAccountId

                // L1: in-memory cache
                if let cached = briefCache[cacheKey],
                   cached.latestMessageID == fetchResult.latestMessageID,
                   cached.promptVersion == AIThreadBriefCacheIdentity.promptVersion,
                   cached.schemaVersion == AIThreadBriefCacheIdentity.schemaVersion {
                    brief = cached.viewData
                    isLoading = false
                    return
                }

                // L2: DB cache
                if let row = try Self.fetchBriefRecord(
                    accountId: resolvedAccountId,
                    threadId: threadID,
                    db: db
                ), row.latestMessageId == fetchResult.latestMessageID,
                   Self.isCurrentCacheRecord(row) {
                    let viewData = ThreadBriefViewData(from: row)
                    cacheBrief(viewData, for: cacheKey, latestMessageID: fetchResult.latestMessageID)
                    brief = viewData
                    isLoading = false
                    return
                }

                try Task.checkCancellation()
                let aiBrief = try await aiService.threadBrief(fetchResult.input)
                try Task.checkCancellation()

                // Persist to DB on a detached task to avoid actor isolation issues
                let language = fetchResult.detectedLanguage
                let latestMessageID = fetchResult.latestMessageID
                try await Task.detached {
                    let record = Self.makeRecord(
                        accountId: resolvedAccountId,
                        threadId: threadID,
                        latestMessageId: latestMessageID,
                        brief: aiBrief,
                        language: language
                    )
                    try db.dbQueue.write { database in
                        try record.save(database)
                    }
                }.value

                let viewData = ThreadBriefViewData(from: aiBrief)
                cacheBrief(viewData, for: cacheKey, latestMessageID: fetchResult.latestMessageID)
                brief = viewData
                isLoading = false
                error = nil
            } catch is CancellationError {
                // Cancelled — don't update state
            } catch let err as AIError where err.isCancelled {
                // AI-level cancellation
            } catch {
                handleBriefFailure(error, threadID: threadID, accountId: accountId)
            }
        }
    }

    public func retry() {
        let id = activeThreadID
        let account = activeAccountId
        activeThreadID = nil
        loadBrief(forThreadID: id, accountId: account)
    }

    // MARK: - Private

    private nonisolated static func fetchBriefRecord(accountId: String, threadId: String, db: AppDatabase) throws -> ThreadBriefRecord? {
        try db.read { database in
            try ThreadBriefRecord.fetchOne(
                database,
                key: ["account_id": accountId, "thread_id": threadId]
            )
        }
    }

    private nonisolated static func fetchThreadData(
        threadID: String,
        accountId: String?,
        db: AppDatabase
    ) throws -> ThreadFetchResult {
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
        let latestMessageID = messages.last?.id ?? ""
        let resolvedAccountId = accountId ?? messages.first?.accountId ?? ""

        // Detect language from incoming messages
        let incoming = messages.filter { $0.flags & MessageRecord.sentByMe == 0 }
        let text = incoming.map(\.bestPlainText).filter { !$0.isEmpty }.joined(separator: "\n")
        var detectedLanguage: String?
        if !text.isEmpty {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            detectedLanguage = recognizer.dominantLanguage?.rawValue
        }

        return ThreadFetchResult(
            input: AIThreadInput(messages: aiMessages, attachments: aiAttachments),
            latestMessageID: latestMessageID,
            resolvedAccountId: resolvedAccountId,
            detectedLanguage: detectedLanguage
        )
    }

    private nonisolated static func encodeEvidence(_ evidence: [String]) -> String {
        (try? JSONEncoder().encode(evidence)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private nonisolated static func makeRecord(
        accountId: String,
        threadId: String,
        latestMessageId: String,
        brief: AIThreadBrief,
        language: String?
    ) -> ThreadBriefRecord {
        ThreadBriefRecord(
            accountId: accountId,
            threadId: threadId,
            latestMessageId: latestMessageId,
            summary: brief.summary,
            request: brief.request,
            deadline: brief.deadline,
            risk: brief.risk,
            nextStep: brief.nextStep,
            confidence: brief.confidence,
            evidenceJson: encodeEvidence(brief.evidence),
            language: language,
            generatedAt: Int(Date().timeIntervalSince1970),
            promptVersion: AIThreadBriefCacheIdentity.promptVersion,
            schemaVersion: AIThreadBriefCacheIdentity.schemaVersion
        )
    }

    private nonisolated static func isCurrentCacheRecord(_ record: ThreadBriefRecord) -> Bool {
        record.promptVersion == AIThreadBriefCacheIdentity.promptVersion
            && record.schemaVersion == AIThreadBriefCacheIdentity.schemaVersion
    }

    private func handleBriefFailure(_ error: any Error, threadID: String, accountId: String?) {
        guard activeThreadID == threadID else { return }
        let kind = Self.failureKind(error)
        Self.logBrief(status: "failed", accountId: accountId, severity: .error, errorCategory: kind)
        self.error = error
        isLoading = false
        brief = nil
    }

    private func cacheBrief(_ viewData: ThreadBriefViewData, for key: BriefCacheKey, latestMessageID: String) {
        briefCache[key] = CacheEntry(
            viewData: viewData,
            latestMessageID: latestMessageID,
            promptVersion: AIThreadBriefCacheIdentity.promptVersion,
            schemaVersion: AIThreadBriefCacheIdentity.schemaVersion
        )
    }

    private nonisolated static func failureKind(_ error: any Error) -> String {
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

    private nonisolated static func logBrief(
        status: String,
        accountId: String?,
        severity: PrivacyObservabilitySeverity = .info,
        errorCategory: String? = nil
    ) {
        var fields: [PrivacyObservabilityField: String] = [
            .operation: "thread_brief",
            .status: status
        ]
        if let accountId, !accountId.isEmpty {
            fields[.accountID] = accountId
        }
        if let errorCategory {
            fields[.errorCategory] = errorCategory
        }
        PrivacyObservability.log(
            PrivacyObservabilityEvent(category: .ai, name: "ai.thread_brief", fields: fields),
            severity: severity
        )
    }
}

// MARK: - Internal types

private struct ThreadFetchResult: Sendable {
    let input: AIThreadInput
    let latestMessageID: String
    let resolvedAccountId: String
    let detectedLanguage: String?
}

private struct BriefCacheKey: Hashable {
    let threadID: String
    let accountId: String
}

private struct CacheEntry {
    let viewData: ThreadBriefViewData
    let latestMessageID: String
    let promptVersion: String?
    let schemaVersion: String?
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

    init(from record: ThreadBriefRecord) {
        let evidence = (try? JSONDecoder().decode([String].self, from: Data((record.evidenceJson).utf8))) ?? []
        self.init(
            summary: record.summary ?? "No summary available",
            request: record.request,
            deadline: record.deadline,
            risk: record.risk,
            nextStep: record.nextStep,
            confidence: record.confidence,
            evidence: evidence
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
