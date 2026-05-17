import Testing
import GRDB
@testable import Persistence

@Suite("Label Migration")
struct LabelMigrationTests {

    @Test func v2CreatesLabelAndThreadLabelTables() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let tables = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        #expect(tables.contains("label"))
        #expect(tables.contains("thread_label"))
    }

    @Test func v2IndexesExist() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let indexes = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_thread_label%' ORDER BY name")
        }
        #expect(indexes.contains("idx_thread_label_label"))
        #expect(indexes.contains("idx_thread_label_thread"))
    }

    @Test func v2MigrationIsIdempotent() async throws {
        let dbQueue = try DatabaseQueue(configuration: .init())
        try Migrator.migrate(dbQueue)
        try Migrator.migrate(dbQueue)
        let tables = try await dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='label'")
        }
        #expect(tables.count == 1)
    }

    @Test func labelRecordRoundTrip() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try LabelRecord(id: "INBOX", accountId: "a1", name: "Inbox", type: .system).insert(db)
                try LabelRecord(id: "Label_123", accountId: "a1", name: "My Label", type: .user, color: "#ff0000").insert(db)
            }
        }

        let labels = try db.read { db in
            try LabelRecord.fetchAll(db)
        }
        #expect(labels.count == 2)
        #expect(labels[0].id == "INBOX")
        #expect(labels[0].type == .system)
        #expect(labels[1].id == "Label_123")
        #expect(labels[1].color == "#ff0000")
    }

    @Test func threadLabelRecordRoundTrip() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try LabelRecord(id: "INBOX", accountId: "a1", name: "Inbox", type: .system).insert(db)
                try LabelRecord(id: "STARRED", accountId: "a1", name: "Starred", type: .system).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadLabelRecord(threadId: "t1", labelId: "INBOX").insert(db)
                try ThreadLabelRecord(threadId: "t1", labelId: "STARRED").insert(db)
            }
        }

        let threadLabels = try db.read { db in
            try ThreadLabelRecord.fetchAll(db)
        }
        #expect(threadLabels.count == 2)
    }

    @Test func labelCascadeDeleteOnAccountRemoval() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try LabelRecord(id: "INBOX", accountId: "a1", name: "Inbox", type: .system).insert(db)
                try LabelRecord(id: "Label_1", accountId: "a1", name: "Work", type: .user).insert(db)
            }
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                _ = try AccountRecord.deleteAll(db)
            }
        }

        let labels = try db.read { db in
            try LabelRecord.fetchCount(db)
        }
        #expect(labels == 0)
    }

    @Test func threadLabelCascadeDeleteOnLabelRemoval() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try LabelRecord(id: "STARRED", accountId: "a1", name: "Starred", type: .system).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadLabelRecord(threadId: "t1", labelId: "STARRED").insert(db)
            }
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                _ = try LabelRecord.deleteAll(db)
            }
        }

        let count = try db.read { db in
            try ThreadLabelRecord.fetchCount(db)
        }
        #expect(count == 0)
    }
}

