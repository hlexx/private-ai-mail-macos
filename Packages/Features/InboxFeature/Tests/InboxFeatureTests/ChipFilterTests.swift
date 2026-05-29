import Testing
import Foundation
@testable import InboxFeature
import Persistence
import GRDB

@Suite("Chip Filter — thread_brief driven")
struct ChipFilterTests {

    // MARK: - Helpers

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.openInMemorySync()
    }

    private func queriedIDs(
        db: AppDatabase,
        selection: SidebarSelection,
        filter: ThreadFilter = .all
    ) throws -> Set<String> {
        try db.dbQueue.read { dbConn in
            let rows = try InboxStore.queryThreads(db: dbConn, selection: selection, filter: filter)
            return Set(rows.map { $0.0.id })
        }
    }

    /// Seeds 3 threads in account acc1, all in INBOX.
    /// - threadA: has a brief with request = "approve invoice"
    /// - threadB: has a brief with deadline = "Friday"
    /// - threadC: no brief at all
    private func seedWithBriefs(db: AppDatabase) throws {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO account (id, email, display_name, provider, created_at) VALUES
                ('acc1', 'user@example.com', 'User', 'gmail', 1000)
                """)

            try dbConn.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread) VALUES
                ('tA', 'acc1', 'Thread A', 'snippetA', 1000, 1, 0),
                ('tB', 'acc1', 'Thread B', 'snippetB', 2000, 1, 0),
                ('tC', 'acc1', 'Thread C', 'snippetC', 3000, 1, 0)
                """)

            try dbConn.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, to_addr, sent_at, flags) VALUES
                ('mA', 'tA', 'acc1', 'a@x.com', 'user@example.com', 1000, 0),
                ('mB', 'tB', 'acc1', 'b@x.com', 'user@example.com', 2000, 0),
                ('mC', 'tC', 'acc1', 'c@x.com', 'user@example.com', 3000, 0)
                """)

            try dbConn.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 'tA', 'INBOX'),
                ('acc1', 'tB', 'INBOX'),
                ('acc1', 'tC', 'INBOX')
                """)

            // Brief for threadA: has request (drives Needs reply)
            try dbConn.execute(sql: """
                INSERT INTO thread_brief (account_id, thread_id, latest_message_id, request, confidence, evidence_json, generated_at)
                VALUES ('acc1', 'tA', 'mA', 'approve invoice', 0.9, '[]', 1000)
                """)

            // Brief for threadB: has deadline (drives Has deadline)
            try dbConn.execute(sql: """
                INSERT INTO thread_brief (account_id, thread_id, latest_message_id, deadline, confidence, evidence_json, generated_at)
                VALUES ('acc1', 'tB', 'mB', 'Friday', 0.8, '[]', 1000)
                """)

            // threadC has no brief row at all
        }
    }

    // MARK: - Chip filter tests

    @MainActor
    @Test func needsReplyChipReturnsThreadsWithRequest() async throws {
        let db = try makeDB()
        try seedWithBriefs(db: db)

        let ids = try queriedIDs(db: db, selection: .folder(.inbox), filter: .needsReply)
        #expect(ids == Set(["tA"]))
    }

    @MainActor
    @Test func hasDeadlineChipReturnsThreadsWithDeadline() async throws {
        let db = try makeDB()
        try seedWithBriefs(db: db)

        let ids = try queriedIDs(db: db, selection: .folder(.inbox), filter: .hasDeadline)
        #expect(ids == Set(["tB"]))
    }

    @MainActor
    @Test func aiHandledChipReturnsAllThreadsWithBriefs() async throws {
        let db = try makeDB()
        try seedWithBriefs(db: db)

        let ids = try queriedIDs(db: db, selection: .folder(.inbox), filter: .aiHandled)
        // tA and tB have briefs, tC does not
        #expect(ids == Set(["tA", "tB"]))
    }

    @MainActor
    @Test func threadWithNoBriefNotInAnyChipFilter() async throws {
        let db = try makeDB()
        try seedWithBriefs(db: db)

        // Check needsReply
        #expect(!((try queriedIDs(db: db, selection: .folder(.inbox), filter: .needsReply)).contains("tC")))

        // Check hasDeadline
        #expect(!((try queriedIDs(db: db, selection: .folder(.inbox), filter: .hasDeadline)).contains("tC")))

        // Check aiHandled
        #expect(!((try queriedIDs(db: db, selection: .folder(.inbox), filter: .aiHandled)).contains("tC")))
    }

    @MainActor
    @Test func allChipShowsEverything() async throws {
        let db = try makeDB()
        try seedWithBriefs(db: db)

        let ids = try queriedIDs(db: db, selection: .folder(.inbox))
        #expect(ids == Set(["tA", "tB", "tC"]))
    }

    // MARK: - Folder sidebar filter tests

    @MainActor
    @Test func needsReplyFolderShowsThreadsWithRequest() async throws {
        let db = try makeDB()
        try seedWithBriefs(db: db)

        let ids = try queriedIDs(db: db, selection: .folder(.needsReply))
        #expect(ids == Set(["tA"]))
    }

    @MainActor
    @Test func hasDeadlineFolderShowsThreadsWithDeadline() async throws {
        let db = try makeDB()
        try seedWithBriefs(db: db)

        let ids = try queriedIDs(db: db, selection: .folder(.hasDeadline))
        #expect(ids == Set(["tB"]))
    }

    // MARK: - Folder counts include brief-driven counts

    @MainActor
    @Test func folderCountsIncludeBriefDrivenCounts() async throws {
        let db = try makeDB()
        try seedWithBriefs(db: db)
        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.startObserving()

        try await Task.sleep(for: .milliseconds(500))

        #expect(store.folderCounts[.needsReply] == 1) // tA
        #expect(store.folderCounts[.hasDeadline] == 1) // tB
    }

    // MARK: - Empty/whitespace brief fields don't count

    @MainActor
    @Test func emptyRequestDoesNotCountAsNeedsReply() async throws {
        let db = try makeDB()
        try await db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO account (id, email, display_name, provider, created_at) VALUES
                ('acc1', 'user@example.com', 'User', 'gmail', 1000)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread) VALUES
                ('t1', 'acc1', 'Thread 1', 'snippet', 1000, 1, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, to_addr, sent_at, flags) VALUES
                ('m1', 't1', 'acc1', 'a@x.com', 'user@example.com', 1000, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 't1', 'INBOX')
                """)
            // Brief with empty request (whitespace only)
            try dbConn.execute(sql: """
                INSERT INTO thread_brief (account_id, thread_id, latest_message_id, request, confidence, evidence_json, generated_at)
                VALUES ('acc1', 't1', 'm1', '   ', 0.5, '[]', 1000)
                """)
        }

        let store = InboxStore(db: db)
        store.setSelection(.folder(.inbox))
        store.filter = .needsReply
        store.startObserving()

        try await Task.sleep(for: .milliseconds(300))

        #expect(store.threads.isEmpty)
    }
}
