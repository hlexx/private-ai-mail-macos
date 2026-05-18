import Foundation
import Testing
import AIKit
import GRDB
import Persistence
@testable import BriefFeature

// MARK: - Test Support

private final class FakeAIService: AIService, @unchecked Sendable {
    var stubbedBrief: AIThreadBrief?
    var callCount = 0

    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        callCount += 1
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

private func makeTestDB() throws -> AppDatabase {
    let db = try AppDatabase.openInMemorySync()
    try db.dbQueue.write { database in
        try database.execute(sql: """
            INSERT INTO account (id, email, provider, display_name, created_at)
            VALUES ('acc1', 'test@example.com', 'gmail', 'Test', 1000)
        """)
        try database.execute(sql: """
            INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread)
            VALUES ('thread-1', 'acc1', 'Test Thread', 'Hello', 1000, 2, 0)
        """)
        try database.execute(sql: """
            INSERT INTO message (id, thread_id, account_id, from_addr, sent_at, body_text, flags)
            VALUES ('msg-1', 'thread-1', 'acc1', 'alice@example.com', 1000, 'Hello world', 0)
        """)
        try database.execute(sql: """
            INSERT INTO message (id, thread_id, account_id, from_addr, sent_at, body_text, flags)
            VALUES ('msg-2', 'thread-1', 'acc1', 'bob@example.com', 2000, 'Can you confirm the seat count by Wednesday?', 0)
        """)
    }
    return db
}

private let sampleBrief = AIThreadBrief(
    summary: "Discussion about seating",
    request: "Confirm seat count",
    deadline: "Wednesday",
    risk: nil,
    nextStep: "Reply with count",
    evidence: ["msg-2"],
    confidence: 0.9
)

// MARK: - Tests

@Suite("BriefPersistence")
struct BriefPersistenceTests {

    @MainActor
    @Test func generatedBriefIsPersistedToDB() async throws {
        let fake = FakeAIService()
        fake.stubbedBrief = sampleBrief
        let db = try makeTestDB()
        let store = BriefStore(aiService: fake, db: db)

        store.loadBrief(forThreadID: "thread-1", accountId: "acc1")
        try await Task.sleep(for: .milliseconds(500))

        #expect(fake.callCount == 1)
        #expect(store.brief != nil)

        // Verify the row landed in DB
        let row = try db.read { database in
            try ThreadBriefRecord.fetchOne(
                database,
                key: ["account_id": "acc1", "thread_id": "thread-1"]
            )
        }
        #expect(row != nil)
        #expect(row?.summary == "Discussion about seating")
        #expect(row?.request == "Confirm seat count")
        #expect(row?.deadline == "Wednesday")
        #expect(row?.latestMessageId == "msg-2")
        #expect(row?.confidence == 0.9)
    }

    @MainActor
    @Test func secondLoadHitsDBNotAI() async throws {
        let fake = FakeAIService()
        fake.stubbedBrief = sampleBrief
        let db = try makeTestDB()

        // First store generates and persists
        let store1 = BriefStore(aiService: fake, db: db)
        store1.loadBrief(forThreadID: "thread-1", accountId: "acc1")
        try await Task.sleep(for: .milliseconds(500))
        #expect(fake.callCount == 1)

        // Second store (fresh, no in-memory cache) should load from DB
        let store2 = BriefStore(aiService: fake, db: db)
        store2.loadBrief(forThreadID: "thread-1", accountId: "acc1")
        try await Task.sleep(for: .milliseconds(300))

        #expect(fake.callCount == 1) // AI not called again
        #expect(store2.brief != nil)
        #expect(store2.brief?.summary == "Discussion about seating")
        #expect(store2.brief?.request == "Confirm seat count")
    }

    @MainActor
    @Test func aiCalledWhenLatestMessageChanges() async throws {
        let fake = FakeAIService()
        fake.stubbedBrief = sampleBrief
        let db = try makeTestDB()

        let store = BriefStore(aiService: fake, db: db)
        store.loadBrief(forThreadID: "thread-1", accountId: "acc1")
        try await Task.sleep(for: .milliseconds(500))
        #expect(fake.callCount == 1)

        // Add a new message to thread-1 (simulates incoming mail)
        try await db.dbQueue.write { database in
            try database.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, sent_at, body_text, flags)
                VALUES ('msg-3', 'thread-1', 'acc1', 'carol@example.com', 3000, 'New message', 0)
            """)
        }

        // Fresh store should see stale latestMessageId and re-invoke AI
        let updatedBrief = AIThreadBrief(
            summary: "Updated discussion",
            request: "Updated request",
            confidence: 0.95
        )
        fake.stubbedBrief = updatedBrief
        let store2 = BriefStore(aiService: fake, db: db)
        store2.loadBrief(forThreadID: "thread-1", accountId: "acc1")
        try await Task.sleep(for: .milliseconds(500))

        #expect(fake.callCount == 2) // AI called again
        #expect(store2.brief?.summary == "Updated discussion")
    }

    @MainActor
    @Test func languageIsDetectedAndStored() async throws {
        let fake = FakeAIService()
        fake.stubbedBrief = sampleBrief
        let db = try makeTestDB()
        let store = BriefStore(aiService: fake, db: db)

        store.loadBrief(forThreadID: "thread-1", accountId: "acc1")
        try await Task.sleep(for: .milliseconds(500))

        let row = try db.read { database in
            try ThreadBriefRecord.fetchOne(
                database,
                key: ["account_id": "acc1", "thread_id": "thread-1"]
            )
        }
        // Messages are in English, so language should be detected as "en"
        #expect(row?.language == "en")
    }
}
