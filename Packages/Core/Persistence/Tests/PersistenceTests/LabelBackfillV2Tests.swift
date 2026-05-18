import Testing
import GRDB
@testable import Persistence

@Suite("M009 Backfill INBOX V2")
struct LabelBackfillV2Tests {

    private func makeDB() async throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(configuration: .init())
        try Migrator.migrate(dbQueue)
        return dbQueue
    }

    private func seedAccount(_ db: Database, id: String = "a1") throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO account (id, provider, email, created_at) VALUES (?, 'gmail', ?, 1000)",
            arguments: [id, "\(id)@gmail.com"]
        )
        try db.execute(
            sql: "INSERT OR IGNORE INTO label (id, account_id, name, type, color, messages_unread_count, messages_total_count) VALUES ('INBOX', ?, 'Inbox', 'system', NULL, 0, 0)",
            arguments: [id]
        )
    }

    private func seedThread(_ db: Database, id: String, accountId: String = "a1") throws {
        try db.execute(
            sql: "INSERT INTO thread (id, account_id, last_message_at, message_count) VALUES (?, ?, 2000, 1)",
            arguments: [id, accountId]
        )
    }

    private func seedLabel(_ db: Database, labelId: String, accountId: String = "a1") throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO label (id, account_id, name, type, color, messages_unread_count, messages_total_count) VALUES (?, ?, ?, 'system', NULL, 0, 0)",
            arguments: [labelId, accountId, labelId]
        )
    }

    private func addThreadLabel(_ db: Database, threadId: String, labelId: String, accountId: String = "a1") throws {
        try seedLabel(db, labelId: labelId, accountId: accountId)
        try db.execute(
            sql: "INSERT OR IGNORE INTO thread_label (account_id, thread_id, label_id) VALUES (?, ?, ?)",
            arguments: [accountId, threadId, labelId]
        )
    }

    private func threadLabels(_ dbQueue: DatabaseQueue, threadId: String, accountId: String = "a1") async throws -> [String] {
        try await dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT label_id FROM thread_label WHERE account_id = ? AND thread_id = ? ORDER BY label_id",
                arguments: [accountId, threadId]
            )
        }
    }

    // Thread A: no labels at all → M009 inserts INBOX
    @Test func threadWithNoLabelsGetsInbox() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tA")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let labels = try await threadLabels(dbQueue, threadId: "tA")
        #expect(labels.contains("INBOX"))
    }

    // Thread B: CATEGORY_PROMOTIONS only → M009 inserts INBOX
    @Test func threadWithCategoryOnlyGetsInbox() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tB")
            try addThreadLabel(db, threadId: "tB", labelId: "CATEGORY_PROMOTIONS")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let labels = try await threadLabels(dbQueue, threadId: "tB")
        #expect(labels.contains("INBOX"))
        #expect(labels.contains("CATEGORY_PROMOTIONS"))
    }

    // Thread C: TRASH → M009 does NOT insert INBOX
    @Test func threadWithTrashDoesNotGetInbox() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tC")
            try addThreadLabel(db, threadId: "tC", labelId: "TRASH")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let labels = try await threadLabels(dbQueue, threadId: "tC")
        #expect(!labels.contains("INBOX"))
        #expect(labels == ["TRASH"])
    }

    // Thread D: SENT only → M009 does NOT insert INBOX (sent-only)
    @Test func sentOnlyThreadDoesNotGetInbox() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tD")
            try addThreadLabel(db, threadId: "tD", labelId: "SENT")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let labels = try await threadLabels(dbQueue, threadId: "tD")
        #expect(!labels.contains("INBOX"))
        #expect(labels == ["SENT"])
    }

    // Thread E: SENT + UNREAD + CATEGORY_FORUMS → M009 inserts INBOX (mixed)
    @Test func sentWithOtherLabelsGetsInbox() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tE")
            try addThreadLabel(db, threadId: "tE", labelId: "SENT")
            try addThreadLabel(db, threadId: "tE", labelId: "UNREAD")
            try addThreadLabel(db, threadId: "tE", labelId: "CATEGORY_FORUMS")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let labels = try await threadLabels(dbQueue, threadId: "tE")
        #expect(labels.contains("INBOX"))
    }

    // Re-run M009 → no duplicate INBOX rows (idempotent)
    @Test func idempotentRerun() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tF")
            try addThreadLabel(db, threadId: "tF", labelId: "CATEGORY_PROMOTIONS")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }
        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let count = try await dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM thread_label WHERE account_id = 'a1' AND thread_id = 'tF' AND label_id = 'INBOX'"
            )
        }
        #expect(count == 1)
    }

    // Thread already has INBOX → M009 does not duplicate
    @Test func threadAlreadyWithInboxUnchanged() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tG")
            try addThreadLabel(db, threadId: "tG", labelId: "INBOX")
            try addThreadLabel(db, threadId: "tG", labelId: "UNREAD")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let labels = try await threadLabels(dbQueue, threadId: "tG")
        let inboxCount = labels.filter { $0 == "INBOX" }.count
        #expect(inboxCount == 1)
    }

    // SPAM exclusion
    @Test func threadWithSpamDoesNotGetInbox() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tH")
            try addThreadLabel(db, threadId: "tH", labelId: "SPAM")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let labels = try await threadLabels(dbQueue, threadId: "tH")
        #expect(!labels.contains("INBOX"))
    }

    // SENT + UNREAD + IMPORTANT only (meta labels) → still sent-only, no INBOX
    @Test func sentWithOnlyMetaLabelsDoesNotGetInbox() async throws {
        let dbQueue = try await makeDB()

        try await dbQueue.write { db in
            try seedAccount(db)
            try seedThread(db, id: "tI")
            try addThreadLabel(db, threadId: "tI", labelId: "SENT")
            try addThreadLabel(db, threadId: "tI", labelId: "UNREAD")
            try addThreadLabel(db, threadId: "tI", labelId: "IMPORTANT")
        }

        try await dbQueue.write { db in
            try M009_BackfillInboxLabelV2.migrate(db)
        }

        let labels = try await threadLabels(dbQueue, threadId: "tI")
        #expect(!labels.contains("INBOX"))
    }
}
