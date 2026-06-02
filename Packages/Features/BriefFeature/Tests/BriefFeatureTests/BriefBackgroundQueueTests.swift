import Foundation
import Testing
import AIKit
import GRDB
import Persistence
@testable import BriefFeature

// MARK: - Test Support

private final class QueueFakeAIService: AIService, @unchecked Sendable {
    var stubbedBrief: AIThreadBrief?
    var callCount = 0
    var delay: Duration?

    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        callCount += 1
        if let delay { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        guard let brief = stubbedBrief else {
            throw AIError.inferenceFailed(NSError(domain: "Test", code: 0))
        }
        return brief
    }

    func draftReply(
        _ input: AIThreadInput,
        tone: AIReplyTone,
        locale: Locale,
        replyLanguage: String?
    ) async throws -> AIThreadReply {
        AIThreadReply(body: "stub", confidence: 0.5)
    }
}

private func makeQueueTestDB(threadCount: Int = 5) throws -> AppDatabase {
    let db = try AppDatabase.openInMemorySync()
    try db.dbQueue.write { database in
        try database.execute(sql: """
            INSERT INTO account (id, email, provider, display_name, created_at)
            VALUES ('acc1', 'test@example.com', 'gmail', 'Test', 1000)
        """)
        for i in 1...threadCount {
            try database.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread)
                VALUES ('thread-\(i)', 'acc1', 'Thread \(i)', 'Snippet', \(1000 + i * 100), 1, 0)
            """)
            try database.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, sent_at, body_text, flags)
                VALUES ('msg-\(i)', 'thread-\(i)', 'acc1', 'sender@example.com', \(1000 + i * 100), 'Body of thread \(i)', 0)
            """)
            try database.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id)
                VALUES ('acc1', 'thread-\(i)', 'INBOX')
            """)
        }
    }
    return db
}

private func briefCount(db: AppDatabase) throws -> Int {
    try db.read { database in
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM thread_brief") ?? 0
    }
}

private func insertBrief(db: AppDatabase, threadId: String, latestMessageId: String, summary: String = "Existing") throws {
    try db.dbQueue.write { database in
        let record = ThreadBriefRecord(
            accountId: "acc1",
            threadId: threadId,
            latestMessageId: latestMessageId,
            summary: summary,
            confidence: 0.8,
            evidenceJson: "[]",
            generatedAt: 1000,
            promptVersion: AIThreadBriefCacheIdentity.promptVersion,
            schemaVersion: AIThreadBriefCacheIdentity.schemaVersion
        )
        try record.save(database)
    }
}

private let queueSampleBrief = AIThreadBrief(
    summary: "Queue test summary",
    request: "Approve invoice",
    deadline: "Wednesday",
    confidence: 0.9
)

// MARK: - Tests

@Suite("BriefBackgroundQueue")
struct BriefBackgroundQueueTests {

    @MainActor
    @Test func enqueueFiveThreadsProducesFiveRows() async throws {
        let fake = QueueFakeAIService()
        fake.stubbedBrief = queueSampleBrief
        let db = try makeQueueTestDB(threadCount: 5)
        let queue = BriefBackgroundQueue(aiService: fake, db: db)

        for i in 1...5 {
            queue.enqueue(accountId: "acc1", threadId: "thread-\(i)")
        }

        try await Task.sleep(for: .seconds(3))

        let count = try briefCount(db: db)
        #expect(count == 5)
        #expect(fake.callCount == 5)
    }

    @MainActor
    @Test func duplicateEnqueueRunsOnce() async throws {
        let fake = QueueFakeAIService()
        fake.stubbedBrief = queueSampleBrief
        let db = try makeQueueTestDB(threadCount: 1)
        let queue = BriefBackgroundQueue(aiService: fake, db: db)

        queue.enqueue(accountId: "acc1", threadId: "thread-1")
        queue.enqueue(accountId: "acc1", threadId: "thread-1")

        try await Task.sleep(for: .seconds(2))

        let count = try briefCount(db: db)
        #expect(count == 1)
        #expect(fake.callCount == 1)
    }

    @MainActor
    @Test func cancelAllStopsProcessing() async throws {
        let fake = QueueFakeAIService()
        fake.stubbedBrief = queueSampleBrief
        fake.delay = .milliseconds(500)
        let db = try makeQueueTestDB(threadCount: 5)
        let queue = BriefBackgroundQueue(aiService: fake, db: db)

        for i in 1...5 {
            queue.enqueue(accountId: "acc1", threadId: "thread-\(i)")
        }

        try await Task.sleep(for: .milliseconds(100))
        queue.cancelAll()

        try await Task.sleep(for: .milliseconds(300))
        #expect(fake.callCount < 5)
        #expect(queue.isRunning == false)
    }

    @MainActor
    @Test func modelNotInstalledPausesQueue() async throws {
        let db = try makeQueueTestDB(threadCount: 2)
        let notInstalledService = ModelNotInstalledService()
        let queue = BriefBackgroundQueue(aiService: notInstalledService, db: db)

        queue.enqueue(accountId: "acc1", threadId: "thread-1")
        queue.enqueue(accountId: "acc1", threadId: "thread-2")

        try await Task.sleep(for: .seconds(2))

        #expect(notInstalledService.callCount <= 1)
    }

    @MainActor
    @Test func setAIUnavailablePreventsProcessingUntilAvailableAgain() async throws {
        let fake = QueueFakeAIService()
        fake.stubbedBrief = queueSampleBrief
        let db = try makeQueueTestDB(threadCount: 1)
        let queue = BriefBackgroundQueue(aiService: fake, db: db)

        queue.setAIAvailable(false)
        queue.enqueue(accountId: "acc1", threadId: "thread-1")

        try await Task.sleep(for: .milliseconds(300))

        #expect(fake.callCount == 0)
        #expect(queue.isRunning == false)

        queue.setAIAvailable(true)
        try await Task.sleep(for: .seconds(1))

        #expect(fake.callCount == 1)
    }

    @MainActor
    @Test func backfillMissingEnqueuesThreadsWithoutBriefs() async throws {
        let fake = QueueFakeAIService()
        fake.stubbedBrief = queueSampleBrief
        let db = try makeQueueTestDB(threadCount: 3)

        try insertBrief(db: db, threadId: "thread-1", latestMessageId: "msg-1")

        let queue = BriefBackgroundQueue(aiService: fake, db: db)
        queue.backfillMissing(limit: 200)

        try await Task.sleep(for: .seconds(3))

        let count = try briefCount(db: db)
        #expect(count == 3)
        #expect(fake.callCount == 2)
    }

    @MainActor
    @Test func refreshCountsUpdatesProperties() async throws {
        let fake = QueueFakeAIService()
        let db = try makeQueueTestDB(threadCount: 3)

        try insertBrief(db: db, threadId: "thread-1", latestMessageId: "msg-1", summary: "Brief 1")
        try insertBrief(db: db, threadId: "thread-2", latestMessageId: "msg-2", summary: "Brief 2")

        let queue = BriefBackgroundQueue(aiService: fake, db: db)
        queue.refreshCounts()
        try await Task.sleep(for: .seconds(1))

        #expect(queue.totalCount == 3)
        #expect(queue.generatedCount == 2)
    }

    @MainActor
    @Test func skipsUpToDateBrief() async throws {
        let fake = QueueFakeAIService()
        fake.stubbedBrief = queueSampleBrief
        let db = try makeQueueTestDB(threadCount: 1)

        try insertBrief(db: db, threadId: "thread-1", latestMessageId: "msg-1", summary: "Already exists")

        let queue = BriefBackgroundQueue(aiService: fake, db: db)
        queue.enqueue(accountId: "acc1", threadId: "thread-1")

        try await Task.sleep(for: .seconds(1))

        #expect(fake.callCount == 0)
    }

    @MainActor
    @Test func regeneratesBriefWithMissingCacheIdentity() async throws {
        let fake = QueueFakeAIService()
        fake.stubbedBrief = queueSampleBrief
        let db = try makeQueueTestDB(threadCount: 1)
        try await db.dbQueue.write { database in
            try ThreadBriefRecord(
                accountId: "acc1",
                threadId: "thread-1",
                latestMessageId: "msg-1",
                summary: "type",
                generatedAt: 1000
            ).insert(database)
        }

        let queue = BriefBackgroundQueue(aiService: fake, db: db)
        queue.enqueue(accountId: "acc1", threadId: "thread-1")

        try await Task.sleep(for: .seconds(1))

        let row = try db.read { database in
            try ThreadBriefRecord.fetchOne(
                database,
                key: ["account_id": "acc1", "thread_id": "thread-1"]
            )
        }
        #expect(fake.callCount == 1)
        #expect(row?.summary == "Queue test summary")
        #expect(row?.promptVersion == AIThreadBriefCacheIdentity.promptVersion)
        #expect(row?.schemaVersion == AIThreadBriefCacheIdentity.schemaVersion)
    }
}

// MARK: - Helper

private final class ModelNotInstalledService: AIService, @unchecked Sendable {
    var callCount = 0

    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        callCount += 1
        throw AIError.modelNotInstalled
    }

    func draftReply(
        _ input: AIThreadInput,
        tone: AIReplyTone,
        locale: Locale,
        replyLanguage: String?
    ) async throws -> AIThreadReply {
        throw AIError.modelNotInstalled
    }
}
