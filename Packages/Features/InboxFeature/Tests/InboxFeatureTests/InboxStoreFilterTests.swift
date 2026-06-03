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
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 't1', 'INBOX'),
                ('acc1', 't1', 'STARRED'),
                ('acc1', 't2', 'INBOX'),
                ('acc2', 't4', 'INBOX'),
                ('acc2', 't5', 'INBOX'),
                ('acc2', 't5', 'SENT'),
                ('acc1', 't3', 'STARRED')
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

        let expected = Set(["t1", "t2", "t4", "t5"])
        let ids = try await waitForThreadIDs(in: store) { $0 == expected }
        #expect(ids == expected)
    }

    @MainActor
    @Test func starredFolderShowsOnlyStarredThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.starred))
        store.startObserving()

        let expected = Set(["t1", "t3"])
        let ids = try await waitForThreadIDs(in: store) { $0 == expected }
        #expect(ids == expected)
    }

    @MainActor
    @Test func sentFolderShowsOnlySentThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.sent))
        store.startObserving()

        let expected = Set(["t5"])
        let ids = try await waitForThreadIDs(in: store) { $0 == expected }
        #expect(ids == expected)
    }

    @MainActor
    @Test func archiveFolderExcludesSystemLabels() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.archive))
        store.startObserving()

        let expected = Set(["t3"])
        let ids = try await waitForThreadIDs(in: store) { $0 == expected }
        #expect(ids == expected)
    }

    @MainActor
    @Test func accountSelectionFiltersToAccount() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.account("acc2"))
        store.startObserving()

        let ids = try await waitForThreadIDs(in: store) { $0 == Set(["t4", "t5"]) }
        #expect(ids == Set(["t4", "t5"]))
    }

    @MainActor
    @Test func attachmentFilterNarrowsResults() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.attachments))
        store.startObserving()

        let expected = Set(["t2"])
        let ids = try await waitForThreadIDs(in: store) { $0 == expected }
        #expect(ids == expected)
    }

    @MainActor
    @Test func chipFilterCombinesWithFolderSelection() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.filter = .hasAttachment
        store.startObserving()

        let expected = Set(["t2"])
        let ids = try await waitForThreadIDs(in: store) { $0 == expected }
        #expect(ids == expected)
    }

    @MainActor
    @Test func changingFilterAfterObservationRefreshesVisibleThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.startObserving()
        defer { store.stopObserving() }

        var ids = try await waitForThreadIDs(in: store) { $0 == Set(["t1", "t2", "t4", "t5"]) }
        #expect(ids == Set(["t1", "t2", "t4", "t5"]))

        store.filter = .hasAttachment
        ids = try await waitForThreadIDs(in: store) { $0 == Set(["t2"]) }
        #expect(ids == Set(["t2"]))

        store.filter = .all
        ids = try await waitForThreadIDs(in: store) { $0 == Set(["t1", "t2", "t4", "t5"]) }
        #expect(ids == Set(["t1", "t2", "t4", "t5"]))
    }

    @MainActor
    @Test func folderCountsArePopulated() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.startObserving()

        let counts = try await waitForFolderCounts(in: store) {
            $0[.inbox] == 4 && $0[.starred] == 2 && $0[.sent] == 1 && $0[.attachments] == 1
        }

        #expect(counts[.inbox] == 4) // t1, t2, t4, t5
        #expect(counts[.starred] == 2) // t1, t3
        #expect(counts[.sent] == 1) // t5
        #expect(counts[.attachments] == 1) // t2
    }

    // MARK: - Account-scoped folder counts

    @MainActor
    @Test func folderCountsScopedToSingleAccount() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.account("acc1"))
        store.startObserving()

        let counts = try await waitForFolderCounts(in: store) {
            $0[.inbox] == 2 && $0[.starred] == 2 && $0[.sent] == 0 && $0[.attachments] == 1
        }

        // acc1 threads: t1 (INBOX, STARRED), t2 (INBOX), t3 (STARRED only)
        #expect(counts[.inbox] == 2) // t1, t2
        #expect(counts[.starred] == 2) // t1, t3
        #expect(counts[.sent] == 0)
        #expect(counts[.attachments] == 1) // t2
    }

    @MainActor
    @Test func folderCountsScopedToSecondAccount() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.account("acc2"))
        store.startObserving()

        let counts = try await waitForFolderCounts(in: store) {
            $0[.inbox] == 2 && $0[.starred] == 0 && $0[.sent] == 1 && $0[.attachments] == 0
        }

        // acc2 threads: t4 (INBOX), t5 (INBOX, SENT)
        #expect(counts[.inbox] == 2) // t4, t5
        #expect(counts[.starred] == 0)
        #expect(counts[.sent] == 1) // t5
        #expect(counts[.attachments] == 0)
    }

    @MainActor
    @Test func folderCountsAllAccountsShowGlobalTotals() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.allAccountsAllFolders)
        store.startObserving()

        let counts = try await waitForFolderCounts(in: store) {
            $0[.inbox] == 4 && $0[.starred] == 2 && $0[.sent] == 1 && $0[.attachments] == 1
        }

        // All threads across both accounts
        #expect(counts[.inbox] == 4) // t1, t2, t4, t5
        #expect(counts[.starred] == 2) // t1, t3
        #expect(counts[.sent] == 1) // t5
        #expect(counts[.attachments] == 1) // t2
    }

    @MainActor
    @Test func folderCountsUpdateWhenSelectionChanges() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)

        // Start with all accounts
        store.setSelection(.allAccountsAllFolders)
        store.startObserving()
        var counts = try await waitForFolderCounts(in: store) { $0[.inbox] == 4 }
        #expect(counts[.inbox] == 4)

        // Switch to acc1 only
        store.setSelection(.account("acc1"))
        counts = try await waitForFolderCounts(in: store) { $0[.inbox] == 2 && $0[.sent] == 0 }
        #expect(counts[.inbox] == 2) // only acc1: t1, t2

        // Switch to acc2 only
        store.setSelection(.account("acc2"))
        counts = try await waitForFolderCounts(in: store) { $0[.inbox] == 2 && $0[.sent] == 1 }
        #expect(counts[.inbox] == 2) // only acc2: t4, t5
    }
}
