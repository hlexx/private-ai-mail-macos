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
                try ThreadLabelRecord(accountId: "a1", threadId: "t1", labelId: "INBOX").insert(db)
                try ThreadLabelRecord(accountId: "a1", threadId: "t1", labelId: "STARRED").insert(db)
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

    @Test func threadLabelPersistsAfterLabelRemoval() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try LabelRecord(id: "STARRED", accountId: "a1", name: "Starred", type: .system).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadLabelRecord(accountId: "a1", threadId: "t1", labelId: "STARRED").insert(db)
            }
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                _ = try LabelRecord.deleteAll(db)
            }
        }

        // thread_label has no FK to label, so rows persist (cleaned on next sync)
        let count = try db.read { db in
            try ThreadLabelRecord.fetchCount(db)
        }
        #expect(count == 1)
    }

    @Test func m005PreservesOrphanedThreadLabelRows() async throws {
        // Verifies that thread_label rows whose label record was deleted
        // before M005 runs are NOT dropped during migration.
        let dbQueue = try DatabaseQueue(configuration: .init())

        var preMigrator = DatabaseMigrator()
        preMigrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        preMigrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        preMigrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        preMigrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        try preMigrator.migrate(dbQueue)

        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO account (id, provider, email, created_at) VALUES ('a1', 'gmail', 'test@gmail.com', 1000)")
            try db.execute(sql: "INSERT INTO label (id, account_id, name, type, messages_unread_count, messages_total_count) VALUES ('INBOX', 'a1', 'Inbox', 'system', 0, 0)")
            try db.execute(sql: "INSERT INTO thread (id, account_id, last_message_at, message_count) VALUES ('t1', 'a1', 2000, 1)")
            // thread_label row referencing INBOX (label exists) and CUSTOM (label deleted)
            try db.execute(sql: "INSERT INTO thread_label (thread_id, label_id) VALUES ('t1', 'INBOX')")
            try db.execute(sql: "INSERT INTO thread_label (thread_id, label_id) VALUES ('t1', 'CUSTOM_DELETED')")
        }

        var fullMigrator = DatabaseMigrator()
        fullMigrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        fullMigrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        fullMigrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        fullMigrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        fullMigrator.registerMigration("M005_ThreadLabelAccountId", migrate: M005_ThreadLabelAccountId.migrate)
        try fullMigrator.migrate(dbQueue)

        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT account_id, thread_id, label_id FROM thread_label ORDER BY label_id")
            // Both rows must survive — including the orphaned CUSTOM_DELETED one
            #expect(rows.count == 2)
            #expect(rows[0]["label_id"] as String == "CUSTOM_DELETED")
            #expect(rows[0]["account_id"] as String == "a1")
            #expect(rows[1]["label_id"] as String == "INBOX")
            #expect(rows[1]["account_id"] as String == "a1")
        }
    }

    @Test func m005PreservesExistingThreadLabelRows() async throws {
        let dbQueue = try DatabaseQueue(configuration: .init())

        // Apply only M001–M004 (pre-M005 schema: thread_label has no account_id)
        var preMigrator = DatabaseMigrator()
        preMigrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        preMigrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        preMigrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        preMigrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        try preMigrator.migrate(dbQueue)

        // Insert legacy data using the old schema (thread_label has thread_id, label_id only)
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO account (id, provider, email, created_at) VALUES ('a1', 'gmail', 'test@gmail.com', 1000)")
            try db.execute(sql: "INSERT INTO label (id, account_id, name, type, messages_unread_count, messages_total_count) VALUES ('INBOX', 'a1', 'Inbox', 'system', 0, 0)")
            try db.execute(sql: "INSERT INTO label (id, account_id, name, type, messages_unread_count, messages_total_count) VALUES ('STARRED', 'a1', 'Starred', 'system', 0, 0)")
            try db.execute(sql: "INSERT INTO thread (id, account_id, last_message_at, message_count) VALUES ('t1', 'a1', 2000, 1)")
            try db.execute(sql: "INSERT INTO thread (id, account_id, last_message_at, message_count) VALUES ('t2', 'a1', 3000, 2)")
            // Old schema: thread_label(thread_id, label_id) — no account_id
            try db.execute(sql: "INSERT INTO thread_label (thread_id, label_id) VALUES ('t1', 'INBOX')")
            try db.execute(sql: "INSERT INTO thread_label (thread_id, label_id) VALUES ('t1', 'STARRED')")
            try db.execute(sql: "INSERT INTO thread_label (thread_id, label_id) VALUES ('t2', 'INBOX')")
        }

        // Now apply M005 which restructures thread_label to include account_id
        var fullMigrator = DatabaseMigrator()
        fullMigrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        fullMigrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        fullMigrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        fullMigrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        fullMigrator.registerMigration("M005_ThreadLabelAccountId", migrate: M005_ThreadLabelAccountId.migrate)
        try fullMigrator.migrate(dbQueue)

        // Verify all 3 rows survived with correct account_id derived from thread table
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT account_id, thread_id, label_id FROM thread_label ORDER BY thread_id, label_id")
            #expect(rows.count == 3)

            #expect(rows[0]["account_id"] as String == "a1")
            #expect(rows[0]["thread_id"] as String == "t1")
            #expect(rows[0]["label_id"] as String == "INBOX")

            #expect(rows[1]["account_id"] as String == "a1")
            #expect(rows[1]["thread_id"] as String == "t1")
            #expect(rows[1]["label_id"] as String == "STARRED")

            #expect(rows[2]["account_id"] as String == "a1")
            #expect(rows[2]["thread_id"] as String == "t2")
            #expect(rows[2]["label_id"] as String == "INBOX")

            // Verify the new schema has account_id in the primary key
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(thread_label)")
            let columnNames = columns.map { $0["name"] as String }
            #expect(columnNames.contains("account_id"))
        }
    }
}

