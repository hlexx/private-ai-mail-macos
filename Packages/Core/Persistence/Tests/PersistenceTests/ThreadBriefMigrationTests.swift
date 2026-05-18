import Testing
import GRDB
@testable import Persistence

@Suite("ThreadBrief Migration")
struct ThreadBriefMigrationTests {

    @Test func m006CreatesThreadBriefTable() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let tables = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        #expect(tables.contains("thread_brief"))
    }

    @Test func m006CreatesIndices() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let indexes = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_thread_brief%' ORDER BY name")
        }
        #expect(indexes.contains("idx_thread_brief_account"))
        #expect(indexes.contains("idx_thread_brief_request"))
        #expect(indexes.contains("idx_thread_brief_deadline"))
        #expect(indexes.count == 3)
    }

    @Test func threadBriefRecordRoundTrip() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadBriefRecord(
                    accountId: "a1",
                    threadId: "t1",
                    latestMessageId: "msg1",
                    summary: "Project update from Alice",
                    request: "approve invoice",
                    deadline: "2026-05-20",
                    risk: "budget overrun",
                    nextStep: "Review and approve",
                    confidence: 0.85,
                    evidenceJson: "[\"msg1\",\"msg2\"]",
                    language: "en",
                    generatedAt: 3000
                ).insert(db)
            }
        }

        let brief = try db.read { db in
            try ThreadBriefRecord.fetchOne(db, sql: "SELECT * FROM thread_brief WHERE account_id = 'a1' AND thread_id = 't1'")
        }
        #expect(brief != nil)
        #expect(brief?.accountId == "a1")
        #expect(brief?.threadId == "t1")
        #expect(brief?.latestMessageId == "msg1")
        #expect(brief?.summary == "Project update from Alice")
        #expect(brief?.request == "approve invoice")
        #expect(brief?.deadline == "2026-05-20")
        #expect(brief?.risk == "budget overrun")
        #expect(brief?.nextStep == "Review and approve")
        #expect(brief?.confidence == 0.85)
        #expect(brief?.evidenceJson == "[\"msg1\",\"msg2\"]")
        #expect(brief?.language == "en")
        #expect(brief?.generatedAt == 3000)
    }

    @Test func threadBriefCascadeDeleteOnAccountRemoval() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadBriefRecord(
                    accountId: "a1",
                    threadId: "t1",
                    latestMessageId: "msg1",
                    generatedAt: 3000
                ).insert(db)
            }
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                _ = try AccountRecord.deleteAll(db)
            }
        }

        let count = try db.read { db in
            try ThreadBriefRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    @Test func threadBriefUpsertOverwritesExistingRow() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadBriefRecord(
                    accountId: "a1",
                    threadId: "t1",
                    latestMessageId: "msg1",
                    summary: "Old summary",
                    generatedAt: 3000
                ).insert(db)
            }
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                let updated = ThreadBriefRecord(
                    accountId: "a1",
                    threadId: "t1",
                    latestMessageId: "msg2",
                    summary: "New summary",
                    request: "please confirm",
                    generatedAt: 4000
                )
                try updated.save(db)
            }
        }

        let count = try db.read { db in
            try ThreadBriefRecord.fetchCount(db)
        }
        #expect(count == 1)

        let brief = try db.read { db in
            try ThreadBriefRecord.fetchOne(db, sql: "SELECT * FROM thread_brief WHERE account_id = 'a1' AND thread_id = 't1'")
        }
        #expect(brief?.latestMessageId == "msg2")
        #expect(brief?.summary == "New summary")
        #expect(brief?.request == "please confirm")
        #expect(brief?.generatedAt == 4000)
    }
}
