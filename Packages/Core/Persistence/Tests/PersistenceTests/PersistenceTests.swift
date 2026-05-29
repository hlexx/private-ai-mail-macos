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

    @Test func accountRecordRoundTripSupportsGmailAndOutlook() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "gmail-1", provider: "gmail", email: "same@example.com", createdAt: 100).insert(db)
                try AccountRecord(id: "outlook-1", provider: "outlook", email: "same@example.com", createdAt: 200).insert(db)
            }
        }

        let fetched = try db.read { db in
            [
                try AccountRecord.fetchOne(db, key: "gmail-1"),
                try AccountRecord.fetchOne(db, key: "outlook-1"),
            ]
        }

        #expect(fetched[0]?.provider == "gmail")
        #expect(fetched[1]?.provider == "outlook")
        #expect(fetched[0]?.email == "same@example.com")
        #expect(fetched[1]?.email == "same@example.com")
    }

    @Test func accountUniquenessIsScopedToProviderAndEmail() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        let duplicateRejected = try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", provider: "gmail", email: "dup@example.com", createdAt: 100).insert(db)
                try AccountRecord(id: "a2", provider: "outlook", email: "dup@example.com", createdAt: 200).insert(db)

                do {
                    try AccountRecord(id: "a3", provider: "gmail", email: "dup@example.com", createdAt: 300).insert(db)
                    return false
                } catch {
                    return true
                }
            }
        }
        #expect(duplicateRejected)

        let accountCount = try db.read { db in
            try AccountRecord.fetchCount(db)
        }
        #expect(accountCount == 2)
    }

    @Test func m014PreservesExistingGmailAccountRowsAndChildren() async throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(configuration: configuration)

        var preMigrator = DatabaseMigrator()
        preMigrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        preMigrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        preMigrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        preMigrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        preMigrator.registerMigration("M005_ThreadLabelAccountId", migrate: M005_ThreadLabelAccountId.migrate)
        preMigrator.registerMigration("M006_ThreadBrief", migrate: M006_ThreadBrief.migrate)
        preMigrator.registerMigration("M007_AttachmentCID", migrate: M007_AttachmentCID.migrate)
        preMigrator.registerMigration("M008_BackfillInboxLabel", migrate: M008_BackfillInboxLabel.migrate)
        preMigrator.registerMigration("M009_BackfillInboxLabelV2", migrate: M009_BackfillInboxLabelV2.migrate)
        preMigrator.registerMigration("M010_SignalLabelReconcile", migrate: M010_SignalLabelReconcile.migrate)
        preMigrator.registerMigration("M011_AttachmentDataPlane", migrate: M011_AttachmentDataPlane.migrate)
        preMigrator.registerMigration("M012_AttachmentBlobStore", migrate: M012_AttachmentBlobStore.migrate)
        preMigrator.registerMigration("M013_ThreadBriefCacheIdentity", migrate: M013_ThreadBriefCacheIdentity.migrate)
        try preMigrator.migrate(dbQueue)

        try await dbQueue.write { db in
            try AccountRecord(id: "gmail-1", provider: "gmail", email: "g@example.com", createdAt: 100).insert(db)
            try SyncStateRecord(accountId: "gmail-1").insert(db)
            try ThreadRecord(id: "tg", accountId: "gmail-1", lastMessageAt: 1, messageCount: 1).insert(db)
            try MessageRecord(id: "mg", threadId: "tg", accountId: "gmail-1", sentAt: 1).insert(db)
            try AttachmentRecord(id: "ag", messageId: "mg", accountId: "gmail-1").insert(db)
        }

        try Migrator.migrate(dbQueue)

        let counts = try await dbQueue.read { db -> [Int] in
            [
                try AccountRecord.fetchCount(db),
                try SyncStateRecord.fetchCount(db),
                try ThreadRecord.fetchCount(db),
                try MessageRecord.fetchCount(db),
                try AttachmentRecord.fetchCount(db),
            ]
        }
        #expect(counts == [1, 1, 1, 1, 1])

        try await dbQueue.write { db in
            try AccountRecord(id: "outlook-1", provider: "outlook", email: "o@example.com", createdAt: 200).insert(db)
        }
        let outlook = try await dbQueue.read { db in
            try AccountRecord.fetchOne(db, key: "outlook-1")
        }
        #expect(outlook?.provider == "outlook")
    }

    @Test func deletingOneAccountCascadesOnlyItsRows() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "gmail-1", provider: "gmail", email: "g@example.com", createdAt: 100).insert(db)
                try AccountRecord(id: "outlook-1", provider: "outlook", email: "o@example.com", createdAt: 200).insert(db)
                try SyncStateRecord(accountId: "gmail-1").insert(db)
                try SyncStateRecord(accountId: "outlook-1").insert(db)
                try ThreadRecord(id: "tg", accountId: "gmail-1", lastMessageAt: 1, messageCount: 1).insert(db)
                try ThreadRecord(id: "to", accountId: "outlook-1", lastMessageAt: 1, messageCount: 1).insert(db)
                try MessageRecord(id: "mg", threadId: "tg", accountId: "gmail-1", sentAt: 1).insert(db)
                try MessageRecord(id: "mo", threadId: "to", accountId: "outlook-1", sentAt: 1).insert(db)
                try AttachmentRecord(id: "ag", messageId: "mg", accountId: "gmail-1").insert(db)
                try AttachmentRecord(id: "ao", messageId: "mo", accountId: "outlook-1").insert(db)
            }
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                _ = try AccountRecord.deleteOne(db, key: "outlook-1")
            }
        }

        let counts = try db.read { db -> [Int] in
            [
                try AccountRecord.fetchCount(db),
                try SyncStateRecord.fetchCount(db),
                try ThreadRecord.fetchCount(db),
                try MessageRecord.fetchCount(db),
                try AttachmentRecord.fetchCount(db),
            ]
        }
        #expect(counts == [1, 1, 1, 1, 1])

        let survivingAccount = try db.read { db in
            try AccountRecord.fetchOne(db, key: "gmail-1")
        }
        #expect(survivingAccount?.provider == "gmail")
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
