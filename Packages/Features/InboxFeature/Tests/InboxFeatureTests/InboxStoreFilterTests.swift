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
                ('t5', 'acc2', 'Thread 5', 'snippet5', 5000, 1, 1),
                ('t6', 'acc1', 'Thread 6', 'snippet6', 6000, 1, 0),
                ('t7', 'acc2', 'Thread 7', 'snippet7', 7000, 1, 0)
                """)

            // Create messages
            try dbConn.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, to_addr, sent_at, flags) VALUES
                ('m1', 't1', 'acc1', 'sender@a.com', 'user@example.com', 1000, 0),
                ('m2', 't2', 'acc1', 'sender@b.com', 'user@example.com', 2000, 0),
                ('m3', 't3', 'acc1', 'sender@c.com', 'user@example.com', 3000, 0),
                ('m4', 't4', 'acc2', 'sender@d.com', 'other@example.com', 4000, 0),
                ('m5', 't5', 'acc2', 'sender@e.com', 'other@example.com', 5000, 0),
                ('m6', 't6', 'acc1', 'sender@f.com', 'user@example.com', 6000, 0),
                ('m7', 't7', 'acc2', 'sender@g.com', 'other@example.com', 7000, 0)
                """)

            // Create labels
            try dbConn.execute(sql: """
                INSERT INTO label (id, account_id, name, type, messages_unread_count, messages_total_count) VALUES
                ('INBOX', 'acc1', 'Inbox', 'system', 0, 0),
                ('STARRED', 'acc1', 'Starred', 'system', 0, 0),
                ('SENT', 'acc1', 'Sent', 'system', 0, 0),
                ('TRASH', 'acc1', 'Trash', 'system', 0, 0),
                ('SPAM', 'acc1', 'Spam', 'system', 0, 0),
                ('INBOX', 'acc2', 'Inbox', 'system', 0, 0),
                ('SENT', 'acc2', 'Sent', 'system', 0, 0),
                ('TRASH', 'acc2', 'Trash', 'system', 0, 0),
                ('SPAM', 'acc2', 'Spam', 'system', 0, 0)
                """)

            // Assign labels to threads
            // t1: INBOX, STARRED
            // t2: INBOX
            // t3: STARRED (not in INBOX = archived but starred)
            // t4: INBOX
            // t5: INBOX, SENT
            // t6: TRASH
            // t7: SPAM
            try dbConn.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 't1', 'INBOX'),
                ('acc1', 't1', 'STARRED'),
                ('acc1', 't2', 'INBOX'),
                ('acc2', 't4', 'INBOX'),
                ('acc2', 't5', 'INBOX'),
                ('acc2', 't5', 'SENT'),
                ('acc1', 't3', 'STARRED'),
                ('acc1', 't6', 'TRASH'),
                ('acc2', 't7', 'SPAM')
                """)

            // Create an attachment for t2
            try dbConn.execute(sql: """
                INSERT INTO attachment (id, message_id, account_id, filename, mime, size_bytes) VALUES
                ('a1', 'm2', 'acc1', 'file.pdf', 'application/pdf', 1024)
                """)
        }
    }

    @MainActor
    private func waitForThreadIDs(
        in store: InboxStore,
        expected: Set<String>
    ) async throws {
        try await waitForThreadIDs(in: store) { $0 == expected }
    }

    @MainActor
    private func waitForThreadIDs(
        in store: InboxStore,
        matching predicate: (Set<String>) -> Bool
    ) async throws {
        for _ in 0..<80 {
            let ids = Set(store.threads.map(\.id))
            if predicate(ids) { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw ObservationWaitTimeout()
    }

    @MainActor
    private func waitForCounts(
        in store: InboxStore,
        expected: [FolderID: Int]
    ) async throws {
        for _ in 0..<80 {
            if expected.allSatisfy({ store.folderCounts[$0.key] == $0.value }) {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw ObservationWaitTimeout()
    }

    private struct ObservationWaitTimeout: Error {}

    // MARK: - Tests

    @MainActor
    @Test func inboxFolderShowsOnlyInboxThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.startObserving()

        try await waitForThreadIDs(in: store, expected: Set(["t1", "t2", "t4", "t5"]))

        let ids = Set(store.threads.map(\.id))
        #expect(ids.contains("t1"))
        #expect(ids.contains("t2"))
        #expect(ids.contains("t4"))
        #expect(ids.contains("t5"))
        #expect(!ids.contains("t3")) // t3 is only STARRED, not INBOX
        #expect(!ids.contains("t6")) // t6 is Trash
        #expect(!ids.contains("t7")) // t7 is Spam
    }

    @MainActor
    @Test func starredFolderShowsOnlyStarredThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.starred))
        store.startObserving()

        try await waitForThreadIDs(in: store, expected: Set(["t1", "t3"]))

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

        try await waitForThreadIDs(in: store, expected: Set(["t5"]))

        let ids = Set(store.threads.map(\.id))
        #expect(ids == Set(["t5"]))
    }

    @MainActor
    @Test func trashFolderShowsOnlyTrashThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.trash))
        store.startObserving()

        try await waitForThreadIDs(in: store, expected: Set(["t6"]))

        let ids = Set(store.threads.map(\.id))
        #expect(ids == Set(["t6"]))
    }

    @MainActor
    @Test func spamFolderShowsOnlySpamThreads() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.spam))
        store.startObserving()

        try await waitForThreadIDs(in: store, expected: Set(["t7"]))

        let ids = Set(store.threads.map(\.id))
        #expect(ids == Set(["t7"]))
    }

    @MainActor
    @Test func archiveFolderExcludesSystemLabels() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.archive))
        store.startObserving()

        try await waitForThreadIDs(in: store, expected: Set(["t3"]))

        // t3 has only STARRED (not INBOX/TRASH/SPAM/SENT/DRAFT) so it's archived
        // t1 has INBOX, t2 has INBOX, t4 has INBOX, t5 has INBOX+SENT
        let ids = Set(store.threads.map(\.id))
        #expect(ids.contains("t3"))
        #expect(!ids.contains("t1"))
        #expect(!ids.contains("t2"))
        #expect(!ids.contains("t6"))
        #expect(!ids.contains("t7"))
    }

    @MainActor
    @Test func accountSelectionFiltersToAccount() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.account("acc2"))
        store.startObserving()

        try await waitForThreadIDs(in: store, expected: Set(["t4", "t5"]))

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

        try await waitForThreadIDs(in: store, expected: Set(["t2"]))

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

        try await waitForThreadIDs(in: store, expected: Set(["t2"]))

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

        try await waitForCounts(
            in: store,
            expected: [
                .inbox: 4,
                .starred: 2,
                .sent: 1,
                .trash: 1,
                .spam: 1,
                .attachments: 1,
            ]
        )

        #expect(store.folderCounts[.inbox] == 4) // t1, t2, t4, t5
        #expect(store.folderCounts[.starred] == 2) // t1, t3
        #expect(store.folderCounts[.sent] == 1) // t5
        #expect(store.folderCounts[.trash] == 1) // t6
        #expect(store.folderCounts[.spam] == 1) // t7
        #expect(store.folderCounts[.attachments] == 1) // t2
    }

    // MARK: - Account-scoped folder counts

    @MainActor
    @Test func folderCountsScopedToSingleAccount() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.account("acc1"))
        store.startObserving()

        try await waitForCounts(
            in: store,
            expected: [
                .inbox: 2,
                .starred: 2,
                .sent: 0,
                .trash: 1,
                .spam: 0,
                .attachments: 1,
            ]
        )

        // acc1 threads: t1 (INBOX, STARRED), t2 (INBOX), t3 (STARRED only)
        #expect(store.folderCounts[.inbox] == 2) // t1, t2
        #expect(store.folderCounts[.starred] == 2) // t1, t3
        #expect(store.folderCounts[.sent] == 0)
        #expect(store.folderCounts[.trash] == 1) // t6
        #expect(store.folderCounts[.spam] == 0)
        #expect(store.folderCounts[.attachments] == 1) // t2
    }

    @MainActor
    @Test func folderCountsScopedToSecondAccount() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.account("acc2"))
        store.startObserving()

        try await waitForCounts(
            in: store,
            expected: [
                .inbox: 2,
                .starred: 0,
                .sent: 1,
                .trash: 0,
                .spam: 1,
                .attachments: 0,
            ]
        )

        // acc2 threads: t4 (INBOX), t5 (INBOX, SENT)
        #expect(store.folderCounts[.inbox] == 2) // t4, t5
        #expect(store.folderCounts[.starred] == 0)
        #expect(store.folderCounts[.sent] == 1) // t5
        #expect(store.folderCounts[.trash] == 0)
        #expect(store.folderCounts[.spam] == 1) // t7
        #expect(store.folderCounts[.attachments] == 0)
    }

    @MainActor
    @Test func folderCountsAllAccountsShowGlobalTotals() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.allAccountsAllFolders)
        store.startObserving()

        try await waitForCounts(
            in: store,
            expected: [
                .inbox: 4,
                .starred: 2,
                .sent: 1,
                .trash: 1,
                .spam: 1,
                .attachments: 1,
            ]
        )

        // All threads across both accounts
        #expect(store.folderCounts[.inbox] == 4) // t1, t2, t4, t5
        #expect(store.folderCounts[.starred] == 2) // t1, t3
        #expect(store.folderCounts[.sent] == 1) // t5
        #expect(store.folderCounts[.trash] == 1) // t6
        #expect(store.folderCounts[.spam] == 1) // t7
        #expect(store.folderCounts[.attachments] == 1) // t2
    }

    @MainActor
    @Test func folderCountsUpdateWhenSelectionChanges() async throws {
        let db = try makeDB()
        try seedData(db: db)
        let store = InboxStore(db: db)

        // Start with all accounts
        store.setSelection(.allAccountsAllFolders)
        store.startObserving()
        try await waitForCounts(in: store, expected: [.inbox: 4])
        #expect(store.folderCounts[.inbox] == 4)

        // Switch to acc1 only
        store.setSelection(.account("acc1"))
        try await waitForCounts(in: store, expected: [.inbox: 2, .trash: 1])
        #expect(store.folderCounts[.inbox] == 2) // only acc1: t1, t2

        // Switch to acc2 only
        store.setSelection(.account("acc2"))
        try await waitForCounts(in: store, expected: [.inbox: 2, .spam: 1])
        #expect(store.folderCounts[.inbox] == 2) // only acc2: t4, t5
    }
}
