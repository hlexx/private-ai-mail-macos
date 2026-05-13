import Testing
import GRDB
@testable import Persistence

@Suite("Persistence")
struct PersistenceTests {

    @Test func migratorAppliesM001AndTablesExist() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let tables = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        #expect(tables.contains("account"))
        #expect(tables.contains("sync_state"))
        #expect(tables.contains("thread"))
        #expect(tables.contains("message"))
        #expect(tables.contains("attachment"))
    }

    @Test func migratorIsIdempotent() async throws {
        let dbQueue = try DatabaseQueue(configuration: .init())
        try Migrator.migrate(dbQueue)
        try Migrator.migrate(dbQueue)
        let tables = try await dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='account'")
        }
        #expect(tables.count == 1)
    }

    @Test func foreignKeyCascadeDeleteAccountRemovesChildren() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try SyncStateRecord(accountId: "a1").insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 2000).insert(db)
                try AttachmentRecord(id: "att1", messageId: "m1", accountId: "a1").insert(db)
            }
        }

        let countsBefore = try db.read { db -> [Int] in
            [
                try SyncStateRecord.fetchCount(db),
                try ThreadRecord.fetchCount(db),
                try MessageRecord.fetchCount(db),
                try AttachmentRecord.fetchCount(db),
            ]
        }
        #expect(countsBefore == [1, 1, 1, 1])

        try await DatabaseActor.shared.run {
            try db.write { db in
                _ = try AccountRecord.deleteAll(db)
            }
        }

        let countsAfter = try db.read { db -> [Int] in
            [
                try SyncStateRecord.fetchCount(db),
                try ThreadRecord.fetchCount(db),
                try MessageRecord.fetchCount(db),
                try AttachmentRecord.fetchCount(db),
            ]
        }
        #expect(countsAfter == [0, 0, 0, 0])
    }

    @Test func recordRoundTrip() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        let account = AccountRecord(id: "a1", email: "user@gmail.com", displayName: "User", createdAt: 100)

        try await DatabaseActor.shared.run {
            try db.write { db in
                try account.insert(db)
            }
        }

        let fetched = try db.read { db in
            try AccountRecord.fetchOne(db, key: "a1")
        }
        #expect(fetched?.email == "user@gmail.com")
        #expect(fetched?.displayName == "User")
        #expect(fetched?.createdAt == 100)
    }

    @Test func indexesExist() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let indexes = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%' ORDER BY name")
        }
        #expect(indexes.contains("idx_thread_last_message"))
        #expect(indexes.contains("idx_message_thread"))
    }
}

extension DatabaseActor {
    func run<T: Sendable>(_ body: @DatabaseActor @Sendable () throws -> T) async rethrows -> T {
        try await body()
    }
}
