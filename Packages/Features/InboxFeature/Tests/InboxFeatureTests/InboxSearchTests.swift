import Foundation
import MailDomain
import MailIndex
import Persistence
import Testing
@testable import InboxFeature

@Suite("InboxStore Search")
struct InboxSearchTests {
    private func makeDB() throws -> AppDatabase {
        try AppDatabase.openInMemorySync()
    }

    private func seedSearchData(db: AppDatabase) throws {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO account (id, email, display_name, provider, created_at) VALUES
                ('acc1', 'user@example.com', 'User', 'gmail', 1000)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread) VALUES
                ('t1', 'acc1', 'Alpha contract', 'first alpha snippet', 1000, 1, 1),
                ('t2', 'acc1', 'Alpha invoice', 'second alpha snippet', 2000, 1, 0),
                ('t3', 'acc1', 'Beta roadmap', 'beta snippet', 3000, 1, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, to_addr, sent_at, snippet, body_text, flags) VALUES
                ('m1', 't1', 'acc1', 'alice@example.com', 'user@example.com', 1000, 'first alpha snippet', 'alpha contract body', 0),
                ('m2', 't2', 'acc1', 'billing@example.com', 'user@example.com', 2000, 'second alpha snippet', 'alpha invoice body', 0),
                ('m3', 't3', 'acc1', 'pm@example.com', 'user@example.com', 3000, 'beta snippet', 'beta roadmap body', 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO label (id, account_id, name, type, messages_unread_count, messages_total_count) VALUES
                ('INBOX', 'acc1', 'Inbox', 'system', 0, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 't1', 'INBOX'),
                ('acc1', 't2', 'INBOX'),
                ('acc1', 't3', 'INBOX')
                """)
            try dbConn.execute(sql: """
                INSERT INTO attachment (id, message_id, account_id, filename, mime, size_bytes) VALUES
                ('a1', 'm2', 'acc1', 'invoice.pdf', 'application/pdf', 1024)
                """)
            try LocalSearchIndexPersistence.rebuildAll(in: dbConn, now: 4_000)
        }
    }

    @MainActor
    @Test func localSearchReturnsIndexedResults() async throws {
        let db = try makeDB()
        try seedSearchData(db: db)
        let store = InboxStore(db: db)

        store.searchText = "contract"
        store.submitSearch()

        try await waitForSearchResults(in: store, expected: ["t1"])
        #expect(store.searchState == .results(query: "contract", count: 1, includesRemoteResults: false))
        #expect(store.filteredThreads.first?.subject == "Alpha contract")
    }

    @MainActor
    @Test func emptySearchShowsEmptyState() async throws {
        let db = try makeDB()
        try seedSearchData(db: db)
        let store = InboxStore(db: db)

        store.searchText = "missing"
        store.submitSearch()

        try await waitForSearchState(in: store) {
            if case .empty(query: "missing") = $0 { return true }
            return false
        }
        #expect(store.filteredThreads.isEmpty)
    }

    @MainActor
    @Test func clearSearchReturnsToNormalInboxFilters() async throws {
        let db = try makeDB()
        try seedSearchData(db: db)
        let store = InboxStore(db: db)
        store.startObserving()
        try await waitForThreadIDs(in: store, expected: ["t1", "t2", "t3"])

        store.searchText = "contract"
        store.submitSearch()
        try await waitForSearchResults(in: store, expected: ["t1"])

        store.clearSearch()

        #expect(store.activeSearchText == nil)
        #expect(Set(store.filteredThreads.map(\.id)) == Set(["t1", "t2", "t3"]))
    }

    @MainActor
    @Test func searchCombinesWithAttachmentFilter() async throws {
        let db = try makeDB()
        try seedSearchData(db: db)
        let store = InboxStore(db: db)
        store.filter = .hasAttachment

        store.searchText = "alpha"
        store.submitSearch()

        try await waitForSearchResults(in: store, expected: ["t2"])
        #expect(store.filteredThreads.first?.attachmentCount == 1)
    }

    @MainActor
    @Test func loadingStateIsVisibleWhileSearchRuns() async throws {
        let db = try makeDB()
        let searcher = StubMailSearching { query in
            try await Task.sleep(for: .milliseconds(120))
            return MailSearchResponse(query: query, results: [])
        }
        let store = InboxStore(db: db, searchService: searcher)

        store.searchText = "alpha"
        store.submitSearch()

        #expect(store.searchState == .loading(query: "alpha"))
        try await waitForSearchState(in: store) {
            if case .empty(query: "alpha") = $0 { return true }
            return false
        }
    }

    @MainActor
    @Test func fallbackFailureIsUserVisibleWithoutDroppingLocalResults() async throws {
        let db = try makeDB()
        try seedSearchData(db: db)
        let localResult = MailSearchResult(
            threadID: "t1",
            accountID: "acc1",
            provider: .gmail,
            subject: "Alpha contract",
            sender: Address(email: "alice@example.com"),
            sentAt: Date(timeIntervalSince1970: 1_000),
            matchedMessageIDs: ["m1"],
            snippets: [MailSearchSnippet(messageID: "m1", field: .snippet, text: "first alpha snippet")],
            canonicalMailboxes: [.inbox],
            isUnread: true,
            source: .local
        )
        let searcher = StubMailSearching { query in
            MailSearchResponse(
                query: query,
                results: [localResult],
                providerFallbackFailures: [
                    MailSearchProviderFallbackFailure(
                        provider: .gmail,
                        userVisibleMessage: "Remote gmail search failed."
                    ),
                ]
            )
        }
        let store = InboxStore(db: db, searchService: searcher)

        store.searchText = "alpha"
        store.submitSearch(mode: .providerFallbackRequest)

        try await waitForSearchResults(in: store, expected: ["t1"])
        #expect(store.searchFallbackMessages == ["Remote gmail search failed."])
        #expect(store.searchWarningText == "Remote gmail search failed.")
    }

    @MainActor
    @Test func searchIsDisabledWhenServiceIsUnavailable() throws {
        let db = try makeDB()
        let store = InboxStore(db: db, searchService: nil)

        store.searchText = "alpha"
        store.submitSearch()

        #expect(store.searchState == .disabled)
        #expect(store.activeSearchText == "alpha")
        #expect(store.filteredThreads.isEmpty)
    }

    @MainActor
    private func waitForSearchResults(
        in store: InboxStore,
        expected: [String]
    ) async throws {
        try await waitForSearchState(in: store) {
            if case .results = $0 {
                return store.filteredThreads.map(\.id) == expected
            }
            return false
        }
    }

    @MainActor
    private func waitForThreadIDs(
        in store: InboxStore,
        expected: Set<String>
    ) async throws {
        for _ in 0..<80 {
            if Set(store.filteredThreads.map(\.id)) == expected { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw WaitTimeout()
    }

    @MainActor
    private func waitForSearchState(
        in store: InboxStore,
        matching predicate: (InboxSearchState) -> Bool
    ) async throws {
        for _ in 0..<80 {
            if predicate(store.searchState) { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw WaitTimeout()
    }

    private struct WaitTimeout: Error {}
}

private actor StubMailSearching: MailSearching {
    private let handler: @Sendable (MailSearchQuery) async throws -> MailSearchResponse

    init(handler: @escaping @Sendable (MailSearchQuery) async throws -> MailSearchResponse) {
        self.handler = handler
    }

    func search(_ query: MailSearchQuery) async throws -> MailSearchResponse {
        try await handler(query)
    }
}
