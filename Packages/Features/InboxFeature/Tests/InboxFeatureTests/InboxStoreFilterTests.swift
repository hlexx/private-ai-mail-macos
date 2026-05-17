import Testing
import Foundation
@testable import InboxFeature
import Persistence
import GRDB

@Suite("InboxStore Filtering")
struct InboxStoreFilterTests {

    // MARK: - Helpers

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.openInMemorySync()
    }

    private func seedData(db: AppDatabase) throws {
        try db.dbQueue.write { dbConn in
            // Create account
            try dbConn.execute(sql: """
                INSERT INTO account (id, email, display_name, provider, created_at) VALUES
                ('acc1', 'user@example.com', 'User', 'gmail', 1000),
                ('acc2', 'other@example.com', 'Other', 'gmail', 1000)
                """)

            // Create threads
            try dbConn.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread) VALUES
                ('t1', 'acc1', 'Thread 1', 'snippet1', 1000, 1, 1),
                ('t2', 'acc1', 'Thread 2', 'snippet2', 2000, 2, 0),
                ('t3', 'acc1', 'Thread 3', 'snippet3', 3000, 1, 1),
                ('t4', 'acc2', 'Thread 4', 'snippet4', 4000, 1, 0),
                ('t5', 'acc2', 'Thread 5', 'snippet5', 5000, 1, 1)
                """)

            // Create messages
            try dbConn.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, to_addr, sent_at, flags) VALUES
                ('m1', 't1', 'acc1', 'sender@a.com', 'user@example.com', 1000, 0),
                ('m2', 't2', 'acc1', 'sender@b.com', 'user@example.com', 2000, 0),
                ('m3', 't3', 'acc1', 'sender@c.com', 'user@example.com', 3000, 0),
                ('m4', 't4', 'acc2', 'sender@d.com', 'other@example.com', 4000, 0),
                ('m5', 't5', 'acc2', 'sender@e.com', 'other@example.com', 5000, 0)
                """)

            // Create labels
            try dbConn.execute(sql: """
                INSERT INTO label (id, account_id, name, type, messages_unread_count, messages_total_count) VALUES
                ('INBOX', 'acc1', 'Inbox', 'system', 0, 0),
                ('STARRED', 'acc1', 'Starred', 'system', 0, 0),
                ('SENT', 'acc1', 'Sent', 'system', 0, 0)
                """)

            // Assign labels to threads
            // t1: INBOX, STARRED
            // t2: INBOX
            // t3: STARRED (not in INBOX = archived but starred)
            // t4: INBOX
            // t5: INBOX, SENT
            try dbConn.execute(sql: """
                INSERT INTO thread_label (thread_id, label_id) VALUES
                ('t1', 'INBOX'),
                ('t1', 'STARRED'),
                ('t2', 'INBOX'),
                ('t4', 'INBOX'),
                ('t5', 'INBOX'),
                ('t5', 'SENT'),
                ('t3', 'STARRED')
                """)

            // Create an attachment for t2
            try dbConn.execute(sql: """
                INSERT INTO attachment (id, message_id, account_id, filename, mime, size_bytes) VALUES
                ('a1', 'm2', 'acc1', 'file.pdf', 'application/pdf', 1024)
                """)
        }
    }

    // MARK: - Tests

    @MainActor
    @Test func inboxFolderShowsOnlyInboxThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.startObserving()

        // Give observation time to emit
        try await Task.sleep(for: .milliseconds(200))

        let ids = Set(store.threads.map(\.id))
        #expect(ids.contains("t1"))
        #expect(ids.contains("t2"))
        #expect(ids.contains("t4"))
        #expect(ids.contains("t5"))
        #expect(!ids.contains("t3")) // t3 is only STARRED, not INBOX
    }

    @MainActor
    @Test func starredFolderShowsOnlyStarredThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.starred))
        store.startObserving()

        try await Task.sleep(for: .milliseconds(200))

        let ids = Set(store.threads.map(\.id))
        #expect(ids.contains("t1"))
        #expect(ids.contains("t3"))
        #expect(!ids.contains("t2"))
        #expect(!ids.contains("t4"))
    }

    @MainActor
    @Test func sentFolderShowsOnlySentThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.sent))
        store.startObserving()

        try await Task.sleep(for: .milliseconds(200))

        let ids = Set(store.threads.map(\.id))
        #expect(ids == Set(["t5"]))
    }

    @MainActor
    @Test func archiveFolderExcludesSystemLabels() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.archive))
        store.startObserving()

        try await Task.sleep(for: .milliseconds(200))

        // t3 has only STARRED (not INBOX/TRASH/SPAM/SENT/DRAFT) so it's archived
        // t1 has INBOX, t2 has INBOX, t4 has INBOX, t5 has INBOX+SENT
        let ids = Set(store.threads.map(\.id))
        #expect(ids.contains("t3"))
        #expect(!ids.contains("t1"))
        #expect(!ids.contains("t2"))
    }

    @MainActor
    @Test func accountSelectionFiltersToAccount() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.account("acc2"))
        store.startObserving()

        try await Task.sleep(for: .milliseconds(200))

        let ids = Set(store.threads.map(\.id))
        #expect(ids == Set(["t4", "t5"]))
    }

    @MainActor
    @Test func attachmentFilterNarrowsResults() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.attachments))
        store.startObserving()

        try await Task.sleep(for: .milliseconds(200))

        let ids = Set(store.threads.map(\.id))
        #expect(ids.contains("t2"))
        #expect(ids.count == 1)
    }

    @MainActor
    @Test func chipFilterCombinesWithFolderSelection() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.filter = .hasAttachment
        store.startObserving()

        try await Task.sleep(for: .milliseconds(200))

        // t2 is in INBOX and has an attachment
        let ids = Set(store.threads.map(\.id))
        #expect(ids.contains("t2"))
        #expect(!ids.contains("t1"))
    }

    @MainActor
    @Test func folderCountsArePopulated() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.startObserving()

        try await Task.sleep(for: .milliseconds(150))

        #expect(store.folderCounts[.inbox] == 4) // t1, t2, t4, t5
        #expect(store.folderCounts[.starred] == 2) // t1, t3
        #expect(store.folderCounts[.sent] == 1) // t5
        #expect(store.folderCounts[.attachments] == 1) // t2
    }
}
