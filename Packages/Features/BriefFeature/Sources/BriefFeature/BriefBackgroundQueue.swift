import AIKit
import Foundation
import GRDB
import NaturalLanguage
import Persistence

/// Processes brief generation for threads in the background, one at a time.
/// MLX is single-model so sequential execution is correct.
@MainActor
public final class BriefBackgroundQueue {
    public private(set) var generatedCount: Int = 0
    public private(set) var totalCount: Int = 0
    public private(set) var isRunning: Bool = false

    private let aiService: any AIService
    private let db: AppDatabase
    private var pending: [ThreadKey] = []
    private var pendingSet: Set<ThreadKey> = []
    private var workerTask: Task<Void, Never>?
    private var aiAvailable: Bool = true
    private var retryTask: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var retryCount: Int = 0
    private static let maxRetries = 10

    public init(aiService: any AIService, db: AppDatabase) {
        self.aiService = aiService
        self.db = db
    }

    public func enqueue(accountId: String, threadId: String) {
        let key = ThreadKey(accountId: accountId, threadId: threadId)
        guard pendingSet.insert(key).inserted else { return }
        pending.append(key)
        startWorkerIfNeeded()
    }

    public func enqueueMany(_ keys: [(accountId: String, threadId: String)]) {
        for key in keys {
            enqueue(accountId: key.accountId, threadId: key.threadId)
        }
    }

    public func cancelAll() {
        workerTask?.cancel()
        workerTask = nil
        retryTask?.cancel()
        retryTask = nil
        backfillTask?.cancel()
        backfillTask = nil
        pending.removeAll()
        pendingSet.removeAll()
        isRunning = false
        retryCount = 0
    }

    public func setAIAvailable(_ available: Bool) {
        aiAvailable = available
        if available {
            retryCount = 0
            retryTask?.cancel()
            retryTask = nil
            startWorkerIfNeeded()
        }
    }

    /// Enqueue all inbox threads that don't have a brief yet, capped at `limit` globally.
    public func backfillMissing(limit: Int = 200) {
        backfillTask?.cancel()
        backfillTask = Task {
            let keys = try? await Task.detached { [db] in
                try db.dbQueue.read { database -> [(accountId: String, threadId: String)] in
                    let rows = try Row.fetchAll(database, sql: """
                        SELECT t.account_id, t.id
                        FROM thread t
                        JOIN thread_label tl ON tl.account_id = t.account_id AND tl.thread_id = t.id AND tl.label_id = 'INBOX'
                        LEFT JOIN thread_brief tb ON tb.account_id = t.account_id AND tb.thread_id = t.id
                        WHERE tb.thread_id IS NULL
                        ORDER BY t.last_message_at DESC
                        LIMIT ?
                        """, arguments: [limit])
                    return rows.map { (accountId: $0["account_id"] as String, threadId: $0["id"] as String) }
                }
            }.value

            guard !Task.isCancelled else { return }
            if let keys, !keys.isEmpty {
                enqueueMany(keys)
            }

            refreshCounts()
        }
    }

    /// Refresh the total/generated counts from DB.
    public func refreshCounts() {
        Task {
            await updateCounts()
        }
    }

    private func updateCounts() async {
        let counts = try? await Task.detached { [db] in
            try db.dbQueue.read { database -> (total: Int, generated: Int) in
                let total = try Int.fetchOne(database, sql: """
                    SELECT COUNT(*) FROM thread t
                    JOIN thread_label tl ON tl.account_id = t.account_id AND tl.thread_id = t.id AND tl.label_id = 'INBOX'
                    """) ?? 0
                let generated = try Int.fetchOne(database, sql: """
                    SELECT COUNT(*) FROM thread_brief tb
                    JOIN thread_label tl ON tl.account_id = tb.account_id AND tl.thread_id = tb.thread_id AND tl.label_id = 'INBOX'
                    """) ?? 0
                return (total, generated)
            }
        }.value
        if let counts {
            totalCount = counts.total
            generatedCount = counts.generated
        }
    }

    // MARK: - Private

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.aiAvailable = true
            self.startWorkerIfNeeded()
        }
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil, !pending.isEmpty, aiAvailable else { return }
        isRunning = true
        workerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard self.aiAvailable else {
                    self.isRunning = false
                    self.workerTask = nil
                    return
                }
                guard let key = self.pending.first else { break }
                self.pending.removeFirst()
                self.pendingSet.remove(key)

                await self.processThread(key)
                await self.updateCounts()
            }
            if let self {
                await self.updateCounts()
                self.isRunning = false
                self.workerTask = nil
            }
        }
    }

    private func processThread(_ key: ThreadKey) async {
        do {
            let fetchResult = try await Task.detached { [db] in
                try BriefStore.fetchThreadDataForQueue(
                    threadID: key.threadId,
                    accountId: key.accountId,
                    db: db
                )
            }.value

            // Skip if brief already exists and is up-to-date
            let existing: ThreadBriefRecord? = try? await Task.detached { [db] in
                try db.dbQueue.read { database in
                    try ThreadBriefRecord.fetchOne(
                        database,
                        key: ["account_id": key.accountId, "thread_id": key.threadId]
                    )
                }
            }.value
            if let existing, existing.latestMessageId == fetchResult.latestMessageID {
                return
            }

            try Task.checkCancellation()
            let aiBrief = try await aiService.threadBrief(fetchResult.input)
            try Task.checkCancellation()

            let language = fetchResult.detectedLanguage
            let latestMessageID = fetchResult.latestMessageID
            try await Task.detached { [db] in
                let record = ThreadBriefRecord(
                    accountId: key.accountId,
                    threadId: key.threadId,
                    latestMessageId: latestMessageID,
                    summary: aiBrief.summary,
                    request: aiBrief.request,
                    deadline: aiBrief.deadline,
                    risk: aiBrief.risk,
                    nextStep: aiBrief.nextStep,
                    confidence: aiBrief.confidence,
                    evidenceJson: Self.encodeEvidence(aiBrief.evidence),
                    language: language,
                    generatedAt: Int(Date().timeIntervalSince1970)
                )
                try db.dbQueue.write { database in
                    try record.save(database)
                }
            }.value
        } catch is CancellationError {
            // Dropped — will be re-queued by backfillMissing on next launch
        } catch let err as AIError {
            switch err {
            case .cancelled:
                break
            case .modelNotInstalled:
                guard !Task.isCancelled else { break }
                retryCount += 1
                if retryCount <= Self.maxRetries {
                    pending.insert(key, at: 0)
                    pendingSet.insert(key)
                    aiAvailable = false
                    scheduleRetry()
                }
            default:
                break
            }
        } catch {
            // Other errors — skip this thread, continue with next
        }
    }

    private nonisolated static func encodeEvidence(_ evidence: [String]) -> String {
        (try? JSONEncoder().encode(evidence)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

// MARK: - ThreadKey

struct ThreadKey: Hashable, Sendable {
    let accountId: String
    let threadId: String
}

// MARK: - BriefStore queue support

extension BriefStore {
    /// Reusable thread-data fetch for the background queue.
    /// Same logic as `fetchThreadData` but with a public static interface.
    nonisolated static func fetchThreadDataForQueue(
        threadID: String,
        accountId: String,
        db: AppDatabase
    ) throws -> QueueFetchResult {
        let (messages, attachments) = try db.dbQueue.read { database in
            let msgs = try MessageRecord
                .filter(Column("thread_id") == threadID && Column("account_id") == accountId)
                .order(Column("sent_at").asc)
                .fetchAll(database)
            let msgIDs = msgs.map(\.id)
            let atts: [AttachmentRecord]
            if msgIDs.isEmpty {
                atts = []
            } else {
                atts = try AttachmentRecord
                    .filter(msgIDs.contains(Column("message_id")) && Column("account_id") == accountId)
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

        let incoming = messages.filter { $0.flags & MessageRecord.sentByMe == 0 }
        let text = incoming.map(\.bestPlainText).filter { !$0.isEmpty }.joined(separator: "\n")
        var detectedLanguage: String?
        if !text.isEmpty {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            detectedLanguage = recognizer.dominantLanguage?.rawValue
        }

        return QueueFetchResult(
            input: AIThreadInput(messages: aiMessages, attachments: aiAttachments),
            latestMessageID: latestMessageID,
            detectedLanguage: detectedLanguage
        )
    }
}

/// Result type for queue-based thread data fetching.
public struct QueueFetchResult: Sendable {
    public let input: AIThreadInput
    public let latestMessageID: String
    public let detectedLanguage: String?
}
