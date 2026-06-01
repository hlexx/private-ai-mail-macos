import AppFoundation
import Foundation
import GRDB
import MailIndex
import Observation
import Persistence

public enum ThreadFilter: String, CaseIterable, Sendable {
    case all
    case needsReply = "reply"
    case hasDeadline = "due"
    case hasAttachment = "att"
    case aiHandled = "ai"

    public var label: String {
        switch self {
        case .all: return String(localized: "filter.all", defaultValue: "All")
        case .needsReply: return String(localized: "filter.needsReply", defaultValue: "Needs reply")
        case .hasDeadline: return String(localized: "filter.hasDeadline", defaultValue: "Has deadline")
        case .hasAttachment: return String(localized: "filter.attachments", defaultValue: "Attachments")
        case .aiHandled: return String(localized: "filter.aiHandled", defaultValue: "AI handled")
        }
    }
}

public enum InboxSearchState: Sendable, Equatable {
    case disabled
    case idle
    case loading(query: String)
    case results(query: String, count: Int, includesRemoteResults: Bool)
    case empty(query: String)
    case failed(query: String, category: UserActionableFailureCategory, message: String)
}

public struct ThreadRow: Identifiable, Sendable, Hashable {
    public let id: String
    public let accountId: String
    public let subject: String
    public let snippet: String
    public let lastMessageAt: Date
    public let messageCount: Int
    public let hasUnread: Bool
    public let senderName: String
    public let senderAddr: String
    public let attachmentCount: Int
    public let isRemoteSearchResult: Bool

    public init(record: ThreadRecord, latestFromAddr: String? = nil, attachmentCount: Int = 0) {
        self.id = record.id
        self.accountId = record.accountId
        self.subject = record.subject ?? "(no subject)"
        self.snippet = record.snippet ?? ""
        self.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(record.lastMessageAt))
        self.messageCount = record.messageCount
        self.hasUnread = record.hasUnread != 0
        self.attachmentCount = attachmentCount

        let addr = latestFromAddr ?? ""
        self.senderAddr = addr
        self.senderName = Self.extractName(from: addr)
        self.isRemoteSearchResult = false
    }

    public init(searchResult: MailSearchResult) {
        self.id = searchResult.threadID
        self.accountId = searchResult.accountID
        self.subject = searchResult.subject ?? "(no subject)"
        self.snippet = Self.snippetText(from: searchResult)
        self.lastMessageAt = searchResult.sentAt
        self.messageCount = max(1, searchResult.matchedMessageIDs.count)
        self.hasUnread = searchResult.isUnread
        self.attachmentCount = searchResult.hasAttachments ? 1 : 0
        self.senderAddr = searchResult.sender?.email ?? ""
        self.senderName = searchResult.sender?.name ?? Self.extractName(from: searchResult.sender?.email ?? "")
        self.isRemoteSearchResult = searchResult.source == .remoteProvider
    }

    static func extractName(from addr: String) -> String {
        let trimmed = addr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "?" }
        if let angleBracket = trimmed.firstIndex(of: "<") {
            let name = trimmed[trimmed.startIndex..<angleBracket]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
        }
        if let at = trimmed.firstIndex(of: "@") {
            return String(trimmed[trimmed.startIndex..<at])
        }
        return trimmed
    }

    private static func snippetText(from result: MailSearchResult) -> String {
        if let snippet = result.snippets.first(where: { $0.field != .subject })?.text {
            return snippet
        }
        return result.snippets.first?.text ?? ""
    }
}

@Observable
@MainActor
public final class InboxStore {
    public private(set) var threads: [ThreadRow] = []
    public private(set) var searchResults: [ThreadRow] = []
    public private(set) var searchState: InboxSearchState
    public private(set) var searchFallbackMessages: [String] = []
    public private(set) var activeSearchText: String?
    public var selectedThreadID: String?
    public var searchText: String = "" {
        didSet {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resetSearchState()
            }
        }
    }
    public var filter: ThreadFilter = .all {
        didSet { if oldValue != filter { refreshForCriteriaChange() } }
    }

    public var selection: SidebarSelection = .default {
        didSet { if oldValue != selection { refreshForCriteriaChange() } }
    }

    public internal(set) var folderCounts: [FolderID: Int] = [:]

    public var filteredThreads: [ThreadRow] {
        activeSearchText == nil ? threads : searchResults
    }

    public var needsReplyCount: Int {
        folderCounts[.needsReply] ?? 0
    }

    public var searchWarningText: String? {
        searchFallbackMessages.first
    }

    let db: AppDatabase
    private let searchService: (any MailSearching)?
    var observationTask: Task<Void, Never>?
    var countsTask: Task<Void, Never>?
    var searchTask: Task<Void, Never>?

    public convenience init(db: AppDatabase) {
        self.init(db: db, searchService: MailSearchService(database: db))
    }

    public init(db: AppDatabase, searchService: (any MailSearching)?) {
        self.db = db
        self.searchService = searchService
        self.searchState = searchService == nil ? .disabled : .idle
    }

    public func setSelection(_ sel: SidebarSelection) {
        selection = sel
    }

    public func submitSearch(mode: MailSearchQueryMode = .localFullText) {
        let queryText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else {
            resetSearchState()
            return
        }

        guard let searchService else {
            activeSearchText = queryText
            searchResults = []
            searchFallbackMessages = []
            searchState = .disabled
            return
        }

        searchTask?.cancel()
        activeSearchText = queryText
        searchResults = []
        searchFallbackMessages = []
        searchState = .loading(query: queryText)

        let currentSelection = selection
        let currentFilter = filter
        let database = db
        searchTask = Task { [weak self, searchService, database] in
            do {
                let query = try MailSearchQuery(
                    text: queryText,
                    filters: Self.searchFilter(selection: currentSelection, filter: currentFilter),
                    mode: mode
                )
                let response = try await searchService.search(query)
                let visibleKeys = try database.read { db in
                    let rows = try Self.queryThreads(db: db, selection: currentSelection, filter: currentFilter)
                    return Set(rows.map { ThreadSearchKey(accountID: $0.0.accountId, threadID: $0.0.id) })
                }
                let visibleResults = response.results.filter {
                    Self.isSearchResultVisible(
                        $0,
                        visibleKeys: visibleKeys,
                        selection: currentSelection,
                        filter: currentFilter
                    )
                }
                let rows = visibleResults.map(ThreadRow.init(searchResult:))
                let fallbackMessages = response.providerFallbackFailures.map(\.userVisibleMessage)

                guard !Task.isCancelled, let self else { return }
                self.searchResults = rows
                self.searchFallbackMessages = fallbackMessages
                if rows.isEmpty {
                    self.searchState = .empty(query: queryText)
                } else {
                    self.searchState = .results(
                        query: queryText,
                        count: rows.count,
                        includesRemoteResults: rows.contains(where: \.isRemoteSearchResult)
                    )
                }
            } catch {
                let failure = Self.userActionableSearchFailure(for: error)
                guard !Task.isCancelled, let self else { return }
                self.searchResults = []
                self.searchFallbackMessages = []
                self.searchState = .failed(
                    query: queryText,
                    category: failure.category,
                    message: failure.message
                )
            }
        }
    }

    public func clearSearch() {
        if !searchText.isEmpty {
            searchText = ""
            return
        }
        resetSearchState()
    }

    public func startObserving() {
        observationTask?.cancel()
        let currentSelection = selection
        let currentFilter = filter
        observationTask = Task { [weak self, db] in
            do {
                let initialRecords = try await Task.detached { [db] in
                    try db.read { database in
                        try Self.queryThreads(
                            db: database,
                            selection: currentSelection,
                            filter: currentFilter
                        )
                    }
                }.value
                guard !Task.isCancelled, let self else { return }
                self.threads = Self.threadRows(from: initialRecords)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.threads = []
            }

            let observation = ValueObservation.tracking { db in
                try Self.queryThreads(db: db, selection: currentSelection, filter: currentFilter)
            }
            do {
                for try await records in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled, let self else { return }
                    self.threads = Self.threadRows(from: records)
                }
            } catch {
                // Observation ended
            }
        }
        startCountsObservation()
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        countsTask?.cancel()
        countsTask = nil
        searchTask?.cancel()
        searchTask = nil
    }

    private func refreshForCriteriaChange() {
        startObserving()
        if activeSearchText != nil {
            submitSearch()
        }
    }

    private func resetSearchState() {
        searchTask?.cancel()
        searchTask = nil
        activeSearchText = nil
        searchResults = []
        searchFallbackMessages = []
        searchState = searchService == nil ? .disabled : .idle
    }

}

private extension InboxStore {
    nonisolated static func searchFilter(
        selection: SidebarSelection,
        filter: ThreadFilter
    ) -> MailSearchFilter {
        var accountIDs: Set<String> = []
        var hasAttachment: Bool?

        if case .account(let accountID) = selection {
            accountIDs.insert(accountID)
        }
        if case .folder(.attachments) = selection {
            hasAttachment = true
        }
        if filter == .hasAttachment {
            hasAttachment = true
        }

        return MailSearchFilter(
            accountIDs: accountIDs,
            hasAttachment: hasAttachment
        )
    }

    nonisolated static func userActionableSearchFailure(for error: any Error) -> UserActionableFailure {
        if let validationError = error as? MailSearchValidationError {
            switch validationError {
            case .incompatibleAttachmentFilter:
                return UserActionableFailure(category: .unsupportedOperation, operation: .search)
            case .emptyFilterValue, .invalidDateRange:
                return UserActionableFailure(category: .unknown, operation: .search)
            }
        }
        return UserActionableFailure.coerce(error, operation: .search)
    }

    nonisolated static func isSearchResultVisible(
        _ result: MailSearchResult,
        visibleKeys: Set<ThreadSearchKey>,
        selection: SidebarSelection,
        filter: ThreadFilter
    ) -> Bool {
        if result.source == .local {
            return visibleKeys.contains(ThreadSearchKey(accountID: result.accountID, threadID: result.threadID))
        }
        return remoteSearchResultMatchesSelection(result, selection: selection)
            && remoteSearchResultMatchesFilter(result, filter: filter)
    }

    nonisolated static func remoteSearchResultMatchesSelection(
        _ result: MailSearchResult,
        selection: SidebarSelection
    ) -> Bool {
        switch selection {
        case .account(let accountID):
            return result.accountID == accountID
        case .allAccountsAllFolders:
            return result.canonicalMailboxes.contains(.inbox)
        case .folder(let folderID):
            if folderID == .attachments {
                return result.hasAttachments
            }
            guard let mailbox = folderID.canonicalMailbox else {
                return false
            }
            return result.canonicalMailboxes.contains(mailbox)
        }
    }

    nonisolated static func remoteSearchResultMatchesFilter(
        _ result: MailSearchResult,
        filter: ThreadFilter
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .hasAttachment:
            return result.hasAttachments
        case .needsReply, .hasDeadline, .aiHandled:
            return false
        }
    }

    nonisolated static func threadRows(
        from records: [(ThreadRecord, String?, Int)]
    ) -> [ThreadRow] {
        records.map { thread, fromAddr, attCount in
            ThreadRow(record: thread, latestFromAddr: fromAddr, attachmentCount: attCount)
        }
    }
}

private struct ThreadSearchKey: Hashable, Sendable {
    let accountID: String
    let threadID: String
}
