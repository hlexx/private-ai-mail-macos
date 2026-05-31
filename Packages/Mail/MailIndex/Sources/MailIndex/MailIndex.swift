import Foundation
import GRDB
import MailDomain
import Persistence

// MARK: - Public API

public enum MailIndex {
    public static let moduleName = "MailIndex"
}

public enum MailSearchQueryMode: Sendable, Equatable {
    case localFullText
    case providerFallbackRequest
}

public enum MailSearchSort: Sendable, Equatable {
    case relevanceThenNewest
    case newestFirst
    case oldestFirst
}

public enum MailAttachmentSizeBucket: String, Sendable, Equatable, CaseIterable {
    case unknown
    case small
    case medium
    case large

    public init(sizeBytes: Int?) {
        guard let sizeBytes, sizeBytes >= 0 else {
            self = .unknown
            return
        }

        if sizeBytes < 100 * 1024 {
            self = .small
        } else if sizeBytes < 1024 * 1024 {
            self = .medium
        } else {
            self = .large
        }
    }
}

public struct MailSearchDateRange: Sendable, Equatable {
    public let start: Date?
    public let end: Date?

    public init(start: Date? = nil, end: Date? = nil) {
        self.start = start
        self.end = end
    }

    public var isEmpty: Bool {
        start == nil && end == nil
    }
}

public enum MailSearchValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyFilterValue(String)
    case invalidDateRange
    case incompatibleAttachmentFilter

    public var description: String {
        switch self {
        case let .emptyFilterValue(name):
            return "\(name) filters must not contain empty values."
        case .invalidDateRange:
            return "Search date range start must be earlier than or equal to end."
        case .incompatibleAttachmentFilter:
            return "Attachment filename or MIME filters cannot be combined with hasAttachment=false."
        }
    }
}

public struct MailSearchFilter: Sendable, Equatable {
    public let accountIDs: Set<String>
    public let providers: Set<MailProviderIdentifier>
    public let canonicalMailboxes: Set<CanonicalMailbox>
    public let from: Set<String>
    public let to: Set<String>
    public let dateRange: MailSearchDateRange?
    public let isUnread: Bool?
    public let isSent: Bool?
    public let hasAttachment: Bool?
    public let attachmentFilenames: Set<String>
    public let attachmentMIMETypes: Set<String>
    public let attachmentSizeBuckets: Set<MailAttachmentSizeBucket>

    public init(
        accountIDs: Set<String> = [],
        providers: Set<MailProviderIdentifier> = [],
        canonicalMailboxes: Set<CanonicalMailbox> = [],
        from: Set<String> = [],
        to: Set<String> = [],
        dateRange: MailSearchDateRange? = nil,
        isUnread: Bool? = nil,
        isSent: Bool? = nil,
        hasAttachment: Bool? = nil,
        attachmentFilenames: Set<String> = [],
        attachmentMIMETypes: Set<String> = [],
        attachmentSizeBuckets: Set<MailAttachmentSizeBucket> = []
    ) {
        self.accountIDs = accountIDs
        self.providers = providers
        self.canonicalMailboxes = canonicalMailboxes
        self.from = from
        self.to = to
        self.dateRange = dateRange
        self.isUnread = isUnread
        self.isSent = isSent
        self.hasAttachment = hasAttachment
        self.attachmentFilenames = attachmentFilenames
        self.attachmentMIMETypes = attachmentMIMETypes
        self.attachmentSizeBuckets = attachmentSizeBuckets
    }

    public var isEmpty: Bool {
        accountIDs.isEmpty
            && providers.isEmpty
            && canonicalMailboxes.isEmpty
            && from.isEmpty
            && to.isEmpty
            && (dateRange?.isEmpty ?? true)
            && isUnread == nil
            && isSent == nil
            && hasAttachment == nil
            && attachmentFilenames.isEmpty
            && attachmentMIMETypes.isEmpty
            && attachmentSizeBuckets.isEmpty
    }

    public func validate() throws {
        try validateNonEmpty(accountIDs, name: "accountID")
        try validateNonEmpty(providers.map(\.rawValue), name: "provider")
        try validateNonEmpty(from, name: "from")
        try validateNonEmpty(to, name: "to")
        try validateNonEmpty(attachmentFilenames, name: "attachmentFilename")
        try validateNonEmpty(attachmentMIMETypes, name: "attachmentMIMEType")

        if let dateRange,
           let start = dateRange.start,
           let end = dateRange.end,
           start > end {
            throw MailSearchValidationError.invalidDateRange
        }

        if hasAttachment == false,
           !attachmentFilenames.isEmpty || !attachmentMIMETypes.isEmpty || !attachmentSizeBuckets.isEmpty {
            throw MailSearchValidationError.incompatibleAttachmentFilter
        }
    }

    public var redactedDescription: String {
        [
            "accounts=\(accountIDs.count)",
            "providers=\(providers.count)",
            "mailboxes=\(canonicalMailboxes.count)",
            "from=\(from.count)",
            "to=\(to.count)",
            "dateRange=\((dateRange?.isEmpty ?? true) ? "none" : "set")",
            "unread=\(redactedBoolean(isUnread))",
            "sent=\(redactedBoolean(isSent))",
            "hasAttachment=\(redactedBoolean(hasAttachment))",
            "attachmentFilenames=\(attachmentFilenames.count)",
            "attachmentMIMETypes=\(attachmentMIMETypes.count)",
            "attachmentSizeBuckets=\(attachmentSizeBuckets.count)",
        ].joined(separator: ",")
    }

    private func validateNonEmpty<S: Sequence>(_ values: S, name: String) throws where S.Element == String {
        if values.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw MailSearchValidationError.emptyFilterValue(name)
        }
    }

    private func redactedBoolean(_ value: Bool?) -> String {
        guard let value else { return "any" }
        return value ? "true" : "false"
    }
}

public struct MailSearchQuery: Sendable, Equatable, CustomStringConvertible {
    public let text: String?
    public let filters: MailSearchFilter
    public let mode: MailSearchQueryMode
    public let sort: MailSearchSort
    public let limit: Int
    public let offset: Int

    public init(
        text: String? = nil,
        filters: MailSearchFilter = MailSearchFilter(),
        mode: MailSearchQueryMode = .localFullText,
        sort: MailSearchSort = .relevanceThenNewest,
        limit: Int = 50,
        offset: Int = 0
    ) throws {
        let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedText = MailSearchTextOperatorParser.parse(normalizedText)
        let effectiveFilters = try filters.applying(parsedText)
        try effectiveFilters.validate()

        self.text = parsedText.text
        self.filters = effectiveFilters
        self.mode = mode
        self.sort = sort
        self.limit = max(1, limit)
        self.offset = max(0, offset)
    }

    public var redactedDescription: String {
        let textDescription = text.map { "<redacted:\($0.count) chars>" } ?? "none"
        return "MailSearchQuery(text=\(textDescription),mode=\(mode),sort=\(sort),limit=\(limit),offset=\(offset),filters={\(filters.redactedDescription)})"
    }

    public var description: String {
        redactedDescription
    }
}

private struct ParsedMailSearchText {
    let text: String?
    let hasAttachment: Bool?
}

private enum MailSearchTextOperatorParser {
    static func parse(_ text: String?) -> ParsedMailSearchText {
        guard let text, !text.isEmpty else {
            return ParsedMailSearchText(text: nil, hasAttachment: nil)
        }

        var hasAttachment: Bool?
        var remainingTokens: [String] = []
        for token in text.split(whereSeparator: \.isWhitespace) {
            switch token.lowercased() {
            case "has:attachment", "has:attachments":
                hasAttachment = true
            default:
                remainingTokens.append(String(token))
            }
        }

        let remainingText = remainingTokens.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedMailSearchText(
            text: remainingText.isEmpty ? nil : remainingText,
            hasAttachment: hasAttachment
        )
    }
}

private extension MailSearchFilter {
    func applying(_ parsedText: ParsedMailSearchText) throws -> MailSearchFilter {
        var effectiveHasAttachment = hasAttachment
        if let parsedHasAttachment = parsedText.hasAttachment {
            if let hasAttachment, hasAttachment != parsedHasAttachment {
                throw MailSearchValidationError.incompatibleAttachmentFilter
            }
            effectiveHasAttachment = parsedHasAttachment
        }

        return MailSearchFilter(
            accountIDs: accountIDs,
            providers: providers,
            canonicalMailboxes: canonicalMailboxes,
            from: from,
            to: to,
            dateRange: dateRange,
            isUnread: isUnread,
            isSent: isSent,
            hasAttachment: effectiveHasAttachment,
            attachmentFilenames: attachmentFilenames,
            attachmentMIMETypes: attachmentMIMETypes,
            attachmentSizeBuckets: attachmentSizeBuckets
        )
    }
}

public enum MailSearchSnippetField: Sendable, Equatable {
    case subject
    case sender
    case recipient
    case cc
    case snippet
    case body
    case attachmentFilename
}

public struct MailSearchSnippet: Sendable, Equatable {
    public let messageID: String
    public let field: MailSearchSnippetField
    public let text: String

    public init(messageID: String, field: MailSearchSnippetField, text: String) {
        self.messageID = messageID
        self.field = field
        self.text = text
    }
}

public enum MailSearchResultSource: Sendable, Equatable {
    case local
    case remoteProvider
}

public struct MailSearchResult: Sendable, Equatable, Identifiable {
    public var id: String { "\(accountID):\(threadID)" }

    public let threadID: String
    public let accountID: String
    public let provider: MailProviderIdentifier
    public let subject: String?
    public let sender: Address?
    public let recipients: [Address]
    public let sentAt: Date
    public let matchedMessageIDs: [String]
    public let snippets: [MailSearchSnippet]
    public let canonicalMailboxes: Set<CanonicalMailbox>
    public let isUnread: Bool
    public let hasAttachments: Bool
    public let source: MailSearchResultSource
    public let score: Double?

    public init(
        threadID: String,
        accountID: String,
        provider: MailProviderIdentifier,
        subject: String? = nil,
        sender: Address? = nil,
        recipients: [Address] = [],
        sentAt: Date,
        matchedMessageIDs: [String] = [],
        snippets: [MailSearchSnippet] = [],
        canonicalMailboxes: Set<CanonicalMailbox> = [],
        isUnread: Bool = false,
        hasAttachments: Bool = false,
        source: MailSearchResultSource = .local,
        score: Double? = nil
    ) {
        self.threadID = threadID
        self.accountID = accountID
        self.provider = provider
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.sentAt = sentAt
        self.matchedMessageIDs = matchedMessageIDs
        self.snippets = snippets
        self.canonicalMailboxes = canonicalMailboxes
        self.isUnread = isUnread
        self.hasAttachments = hasAttachments
        self.source = source
        self.score = score
    }
}

public struct MailSearchResponse: Sendable, Equatable {
    public let query: MailSearchQuery
    public let results: [MailSearchResult]
    public let localResultsComplete: Bool
    public let totalResultCount: Int?
    public let providerFallbackFailures: [MailSearchProviderFallbackFailure]

    public init(
        query: MailSearchQuery,
        results: [MailSearchResult],
        localResultsComplete: Bool = true,
        totalResultCount: Int? = nil,
        providerFallbackFailures: [MailSearchProviderFallbackFailure] = []
    ) {
        self.query = query
        self.results = results
        self.localResultsComplete = localResultsComplete
        self.totalResultCount = totalResultCount
        self.providerFallbackFailures = providerFallbackFailures
    }
}

public struct MailSearchProviderFallbackRequest: Sendable, Equatable {
    public let provider: MailProviderIdentifier
    public let query: MailSearchQuery

    public init(provider: MailProviderIdentifier, query: MailSearchQuery) {
        self.provider = provider
        self.query = query
    }
}

public struct MailSearchProviderFallbackResponse: Sendable, Equatable {
    public let provider: MailProviderIdentifier
    public let results: [MailSearchResult]
    public let totalResultCount: Int?

    public init(
        provider: MailProviderIdentifier,
        results: [MailSearchResult],
        totalResultCount: Int? = nil
    ) {
        self.provider = provider
        self.results = results
        self.totalResultCount = totalResultCount
    }
}

public struct MailSearchProviderFallbackFailure: Sendable, Equatable {
    public let provider: MailProviderIdentifier
    public let userVisibleMessage: String

    public init(provider: MailProviderIdentifier, userVisibleMessage: String) {
        self.provider = provider
        self.userVisibleMessage = userVisibleMessage
    }
}

public struct MailIndexedAttachment: Sendable, Equatable {
    public let filename: String?
    public let mime: String?
    public let sizeBytes: Int?

    public init(filename: String? = nil, mime: String? = nil, sizeBytes: Int? = nil) {
        self.filename = filename
        self.mime = mime
        self.sizeBytes = sizeBytes
    }

    public var sizeBucket: MailAttachmentSizeBucket {
        MailAttachmentSizeBucket(sizeBytes: sizeBytes)
    }
}

public struct MailIndexedMessage: Sendable, Equatable {
    public let messageID: String
    public let threadID: String
    public let accountID: String
    public let provider: MailProviderIdentifier
    public let subject: String?
    public let sender: Address?
    public let recipients: [Address]
    public let cc: [Address]
    public let sentAt: Date
    public let snippet: String?
    public let bodyText: String?
    public let normalizedBodyText: String?
    public let canonicalMailboxes: Set<CanonicalMailbox>
    public let isUnread: Bool
    public let isSent: Bool
    public let attachments: [MailIndexedAttachment]

    public init(
        messageID: String,
        threadID: String,
        accountID: String,
        provider: MailProviderIdentifier,
        subject: String? = nil,
        sender: Address? = nil,
        recipients: [Address] = [],
        cc: [Address] = [],
        sentAt: Date,
        snippet: String? = nil,
        bodyText: String? = nil,
        normalizedBodyText: String? = nil,
        canonicalMailboxes: Set<CanonicalMailbox> = [],
        isUnread: Bool = false,
        isSent: Bool = false,
        attachments: [MailIndexedAttachment] = []
    ) {
        self.messageID = messageID
        self.threadID = threadID
        self.accountID = accountID
        self.provider = provider
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.cc = cc
        self.sentAt = sentAt
        self.snippet = snippet
        self.bodyText = bodyText
        self.normalizedBodyText = normalizedBodyText
        self.canonicalMailboxes = canonicalMailboxes
        self.isUnread = isUnread
        self.isSent = isSent
        self.attachments = attachments
    }
}

public protocol MailIndexing: Sendable {
    func upsert(_ messages: [MailIndexedMessage]) async throws
    func deleteMessages(messageIDs: Set<String>, accountID: String?) async throws
    func rebuild(accountIDs: Set<String>?) async throws
}

public protocol MailSearching: Sendable {
    func search(_ query: MailSearchQuery) async throws -> MailSearchResponse
}

public protocol MailProviderSearchFallback: Sendable {
    var provider: MailProviderIdentifier { get }

    func search(_ request: MailSearchProviderFallbackRequest) async throws -> MailSearchProviderFallbackResponse
}

// MARK: - Local Search Execution

public struct MailSearchService: MailSearching {
    private let database: AppDatabase
    private let providerFallbacks: [any MailProviderSearchFallback]

    public init(database: AppDatabase, providerFallbacks: [any MailProviderSearchFallback] = []) {
        self.database = database
        self.providerFallbacks = providerFallbacks
    }

    public func search(_ query: MailSearchQuery) async throws -> MailSearchResponse {
        let localResponse = try localSearch(query)

        guard query.mode == .providerFallbackRequest else {
            return localResponse
        }

        let fallbackResponse = await searchProviderFallbacks(for: query)
        let results = localResponse.results + fallbackResponse.results
        let totalResultCount = fallbackResponse.totalResultCount.map {
            (localResponse.totalResultCount ?? localResponse.results.count) + $0
        }
        return MailSearchResponse(
            query: query,
            results: results,
            localResultsComplete: false,
            totalResultCount: totalResultCount ?? results.count,
            providerFallbackFailures: fallbackResponse.failures
        )
    }

    private func localSearch(_ query: MailSearchQuery) throws -> MailSearchResponse {
        guard query.text != nil || !query.filters.isEmpty else {
            return MailSearchResponse(query: query, results: [], totalResultCount: 0)
        }

        let rows = try database.read { db in
            try SearchSQL(query: query).fetchRows(in: db)
        }
        let ranked = SearchResultBuilder(query: query).makeResults(from: rows)
        let sliced = Array(ranked.dropFirst(query.offset).prefix(query.limit))

        return MailSearchResponse(
            query: query,
            results: sliced,
            totalResultCount: ranked.count
        )
    }

    private func searchProviderFallbacks(for query: MailSearchQuery) async -> ProviderFallbackAggregate {
        var results: [MailSearchResult] = []
        var failures: [MailSearchProviderFallbackFailure] = []
        var totalResultCount = 0
        var hasUnknownTotalResultCount = false
        for fallback in providerFallbacksForQuery(query) {
            do {
                let request = MailSearchProviderFallbackRequest(provider: fallback.provider, query: query)
                let response = try await fallback.search(request)
                results.append(contentsOf: response.results.map(remoteProviderResult))
                if let responseTotal = response.totalResultCount {
                    totalResultCount += responseTotal
                } else {
                    totalResultCount += response.results.count
                    hasUnknownTotalResultCount = true
                }
            } catch {
                failures.append(MailSearchProviderFallbackFailure(
                    provider: fallback.provider,
                    userVisibleMessage: "Remote \(fallback.provider.rawValue) search failed."
                ))
            }
        }
        return ProviderFallbackAggregate(
            results: results,
            failures: failures,
            totalResultCount: hasUnknownTotalResultCount ? nil : totalResultCount
        )
    }

    private func providerFallbacksForQuery(_ query: MailSearchQuery) -> [any MailProviderSearchFallback] {
        guard !query.filters.providers.isEmpty else { return providerFallbacks }
        return providerFallbacks.filter { query.filters.providers.contains($0.provider) }
    }

    private func remoteProviderResult(_ result: MailSearchResult) -> MailSearchResult {
        MailSearchResult(
            threadID: result.threadID,
            accountID: result.accountID,
            provider: result.provider,
            subject: result.subject,
            sender: result.sender,
            recipients: result.recipients,
            sentAt: result.sentAt,
            matchedMessageIDs: result.matchedMessageIDs,
            snippets: result.snippets,
            canonicalMailboxes: result.canonicalMailboxes,
            isUnread: result.isUnread,
            hasAttachments: result.hasAttachments,
            source: .remoteProvider,
            score: result.score
        )
    }
}

private struct ProviderFallbackAggregate {
    let results: [MailSearchResult]
    let failures: [MailSearchProviderFallbackFailure]
    let totalResultCount: Int?
}

private struct SearchSQL {
    let query: MailSearchQuery

    func fetchRows(in db: Database) throws -> [SearchRow] {
        let filter = FilterSQL(filters: query.filters)
        let sql: String
        var arguments: [DatabaseValueConvertible] = []

        if let text = query.text {
            let ftsQuery = FTSQueryBuilder.makeQuery(text)
            guard !ftsQuery.isEmpty else { return [] }
            arguments.append(ftsQuery)
            arguments.append(contentsOf: filter.arguments)
            sql = """
                SELECT
                    d.account_id,
                    d.message_id,
                    d.thread_id,
                    d.provider,
                    d.subject,
                    d.from_addr,
                    d.to_addr,
                    d.cc_addr,
                    d.snippet,
                    d.body_text,
                    d.normalized_body_text,
                    d.attachment_filenames,
                    d.attachment_mimes,
                    d.attachment_size_buckets,
                    d.canonical_mailboxes,
                    d.sent_at,
                    d.is_unread,
                    d.is_sent,
                    d.has_attachment,
                    -bm25(mail_search_fts, 6.0, 5.0, 2.5, 1.5, 1.0, 1.0, 1.0, 2.0, 1.2, 0.5, 1.0) AS fts_score
                FROM mail_search_fts
                JOIN mail_search_document d ON d.id = mail_search_fts.rowid
                \(filter.joinedWhere(prefix: "mail_search_fts MATCH ?"))
                """
        } else {
            arguments.append(contentsOf: filter.arguments)
            sql = """
                SELECT
                    d.account_id,
                    d.message_id,
                    d.thread_id,
                    d.provider,
                    d.subject,
                    d.from_addr,
                    d.to_addr,
                    d.cc_addr,
                    d.snippet,
                    d.body_text,
                    d.normalized_body_text,
                    d.attachment_filenames,
                    d.attachment_mimes,
                    d.attachment_size_buckets,
                    d.canonical_mailboxes,
                    d.sent_at,
                    d.is_unread,
                    d.is_sent,
                    d.has_attachment,
                    0.0 AS fts_score
                FROM mail_search_document d
                \(filter.joinedWhere())
                """
        }

        return try SearchRow.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }
}

private struct FilterSQL {
    let whereClauses: [String]
    let arguments: [DatabaseValueConvertible]

    init(filters: MailSearchFilter) {
        var clauses: [String] = []
        var args: [DatabaseValueConvertible] = []

        Self.appendInClause("d.account_id", values: filters.accountIDs.sorted(), clauses: &clauses, arguments: &args)
        Self.appendInClause("d.provider", values: filters.providers.map(\.rawValue).sorted(), clauses: &clauses, arguments: &args)

        if !filters.canonicalMailboxes.isEmpty {
            let tokens = filters.canonicalMailboxes
                .flatMap(Self.mailboxTokens)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !tokens.isEmpty {
                let parts = tokens.map { _ in "(' ' || COALESCE(d.canonical_mailboxes, '') || ' ') LIKE ?" }
                clauses.append("(\(parts.joined(separator: " OR ")))")
                args.append(contentsOf: tokens.map { "% \($0) %" })
            }
        }

        Self.appendLikeClause("d.from_addr", values: filters.from.sorted(), clauses: &clauses, arguments: &args)
        Self.appendLikeClause("d.to_addr", values: filters.to.sorted(), clauses: &clauses, arguments: &args)

        if let start = filters.dateRange?.start {
            clauses.append("d.sent_at >= ?")
            args.append(Int(start.timeIntervalSince1970))
        }
        if let end = filters.dateRange?.end {
            clauses.append("d.sent_at <= ?")
            args.append(Int(end.timeIntervalSince1970))
        }
        if let isUnread = filters.isUnread {
            clauses.append("d.is_unread = ?")
            args.append(isUnread ? 1 : 0)
        }
        if let isSent = filters.isSent {
            clauses.append("d.is_sent = ?")
            args.append(isSent ? 1 : 0)
        }
        if let hasAttachment = filters.hasAttachment {
            clauses.append("d.has_attachment = ?")
            args.append(hasAttachment ? 1 : 0)
        }

        Self.appendLikeClause("d.attachment_filenames", values: filters.attachmentFilenames.sorted(), clauses: &clauses, arguments: &args)
        Self.appendLikeClause("d.attachment_mimes", values: filters.attachmentMIMETypes.sorted(), clauses: &clauses, arguments: &args)
        Self.appendTokenClause(
            "d.attachment_size_buckets",
            values: filters.attachmentSizeBuckets.map(\.rawValue).sorted(),
            clauses: &clauses,
            arguments: &args
        )

        whereClauses = clauses
        arguments = args
    }

    func joinedWhere(prefix: String? = nil) -> String {
        var clauses = whereClauses
        if let prefix {
            clauses.insert(prefix, at: 0)
        }
        return clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))"
    }

    private static func appendInClause(
        _ column: String,
        values: [String],
        clauses: inout [String],
        arguments: inout [DatabaseValueConvertible]
    ) {
        guard !values.isEmpty else { return }
        clauses.append("\(column) IN (\(Array(repeating: "?", count: values.count).joined(separator: ", ")))")
        arguments.append(contentsOf: values)
    }

    private static func appendLikeClause(
        _ column: String,
        values: [String],
        clauses: inout [String],
        arguments: inout [DatabaseValueConvertible]
    ) {
        guard !values.isEmpty else { return }
        clauses.append("(\(values.map { _ in "LOWER(COALESCE(\(column), '')) LIKE ?" }.joined(separator: " OR ")))")
        arguments.append(contentsOf: values.map { "%\($0.lowercased())%" })
    }

    private static func appendTokenClause(
        _ column: String,
        values: [String],
        clauses: inout [String],
        arguments: inout [DatabaseValueConvertible]
    ) {
        guard !values.isEmpty else { return }
        clauses.append("(\(values.map { _ in "(' ' || COALESCE(\(column), '') || ' ') LIKE ?" }.joined(separator: " OR ")))")
        arguments.append(contentsOf: values.map { "% \($0) %" })
    }

    private static func mailboxTokens(for mailbox: CanonicalMailbox) -> [String] {
        switch mailbox {
        case .inbox:
            return ["INBOX"]
        case .sent:
            return ["SENT"]
        case .drafts:
            return ["DRAFT"]
        case .trash:
            return ["TRASH"]
        case .spam:
            return ["SPAM"]
        case .archive:
            return ["ARCHIVE"]
        case .starred, .flagged:
            return ["STARRED"]
        case .userDefined(let id, _, _):
            return [id]
        }
    }
}

private enum FTSQueryBuilder {
    static func makeQuery(_ text: String) -> String {
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " AND ")
    }
}

private struct SearchRow: FetchableRecord {
    let accountID: String
    let messageID: String
    let threadID: String
    let provider: MailProviderIdentifier
    let subject: String?
    let from: String?
    let to: String?
    let cc: String?
    let snippet: String?
    let bodyText: String?
    let normalizedBodyText: String?
    let attachmentFilenames: String?
    let attachmentMIMEs: String?
    let attachmentSizeBuckets: String?
    let canonicalMailboxes: String?
    let sentAt: Int
    let isUnread: Bool
    let isSent: Bool
    let hasAttachment: Bool
    let ftsScore: Double

    init(row: Row) {
        accountID = row["account_id"]
        messageID = row["message_id"]
        threadID = row["thread_id"]
        provider = MailProviderIdentifier(rawValue: row["provider"])
        subject = row["subject"]
        from = row["from_addr"]
        to = row["to_addr"]
        cc = row["cc_addr"]
        snippet = row["snippet"]
        bodyText = row["body_text"]
        normalizedBodyText = row["normalized_body_text"]
        attachmentFilenames = row["attachment_filenames"]
        attachmentMIMEs = row["attachment_mimes"]
        attachmentSizeBuckets = row["attachment_size_buckets"]
        canonicalMailboxes = row["canonical_mailboxes"]
        sentAt = row["sent_at"]
        isUnread = (row["is_unread"] as Int) != 0
        isSent = (row["is_sent"] as Int) != 0
        hasAttachment = (row["has_attachment"] as Int) != 0
        ftsScore = row["fts_score"] ?? 0
    }
}

private struct SearchResultBuilder {
    let query: MailSearchQuery

    func makeResults(from rows: [SearchRow]) -> [MailSearchResult] {
        let groups = Dictionary(grouping: rows) { row in
            ResultKey(accountID: row.accountID, threadID: row.threadID)
        }

        return groups.values
            .map(makeResult)
            .sorted(by: sortResults)
    }

    private func makeResult(from rows: [SearchRow]) -> MailSearchResult {
        let sortedRows = rows.sorted {
            if $0.sentAt == $1.sentAt { return $0.messageID < $1.messageID }
            return $0.sentAt > $1.sentAt
        }
        let displayRow = sortedRows.first!
        let bestScore = rows.map(score).max() ?? 0
        let matchedMessageIDs = sortedRows.map(\.messageID)
        let snippets = rows
            .sorted { score($0) > score($1) }
            .flatMap(makeSnippets)
            .prefix(4)

        return MailSearchResult(
            threadID: displayRow.threadID,
            accountID: displayRow.accountID,
            provider: displayRow.provider,
            subject: displayRow.subject,
            sender: displayRow.from.flatMap(Address.init(rfc822:)),
            recipients: parseAddresses(displayRow.to),
            sentAt: Date(timeIntervalSince1970: TimeInterval(sortedRows.map(\.sentAt).max() ?? displayRow.sentAt)),
            matchedMessageIDs: matchedMessageIDs,
            snippets: Array(snippets),
            canonicalMailboxes: Set(rows.flatMap { parseMailboxes($0.canonicalMailboxes) }),
            isUnread: rows.contains { $0.isUnread },
            hasAttachments: rows.contains { $0.hasAttachment },
            score: bestScore
        )
    }

    private func sortResults(_ lhs: MailSearchResult, _ rhs: MailSearchResult) -> Bool {
        switch query.sort {
        case .relevanceThenNewest:
            let leftScore = lhs.score ?? 0
            let rightScore = rhs.score ?? 0
            if abs(leftScore - rightScore) > 0.0001 { return leftScore > rightScore }
            if lhs.sentAt != rhs.sentAt { return lhs.sentAt > rhs.sentAt }
            return lhs.id < rhs.id
        case .newestFirst:
            if lhs.sentAt != rhs.sentAt { return lhs.sentAt > rhs.sentAt }
            return lhs.id < rhs.id
        case .oldestFirst:
            if lhs.sentAt != rhs.sentAt { return lhs.sentAt < rhs.sentAt }
            return lhs.id < rhs.id
        }
    }

    private func score(_ row: SearchRow) -> Double {
        guard let text = query.text?.lowercased(), !text.isEmpty else {
            return Double(row.sentAt) / 1_000_000_000
        }

        var score = row.ftsScore
        if contains(row.subject, text) { score += 80 }
        if contains(row.from, text) { score += 60 }
        if contains(row.to, text) { score += 20 }
        if contains(row.cc, text) { score += 15 }
        if contains(row.snippet, text) { score += 15 }
        if contains(row.bodyText, text) || contains(row.normalizedBodyText, text) { score += 10 }
        if contains(row.attachmentFilenames, text) { score += 12 }
        if contains(row.attachmentMIMEs, text) { score += 8 }
        if contains(row.attachmentSizeBuckets, text) { score += 3 }
        score += Double(row.sentAt) / 1_000_000_000
        return score
    }

    private func makeSnippets(for row: SearchRow) -> [MailSearchSnippet] {
        let candidates: [(MailSearchSnippetField, String?)] = [
            (.subject, row.subject),
            (.sender, row.from),
            (.recipient, row.to),
            (.cc, row.cc),
            (.snippet, row.snippet),
            (.body, row.bodyText ?? row.normalizedBodyText),
            (.attachmentFilename, row.attachmentFilenames),
        ]
        let matched = candidates.compactMap { field, value -> MailSearchSnippet? in
            guard let value, !value.isEmpty else { return nil }
            if !matchesQuery(value) {
                return nil
            }
            return MailSearchSnippet(
                messageID: row.messageID,
                field: field,
                text: excerpt(value, around: query.text)
            )
        }

        if !matched.isEmpty { return Array(matched.prefix(2)) }
        if let snippet = row.snippet, !snippet.isEmpty {
            return [MailSearchSnippet(messageID: row.messageID, field: .snippet, text: excerpt(snippet, around: nil))]
        }
        if let subject = row.subject, !subject.isEmpty {
            return [MailSearchSnippet(messageID: row.messageID, field: .subject, text: excerpt(subject, around: nil))]
        }
        return []
    }

    private func parseAddresses(_ value: String?) -> [Address] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .compactMap { Address(rfc822: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func parseMailboxes(_ value: String?) -> [CanonicalMailbox] {
        guard let value else { return [] }
        return value
            .split(separator: " ")
            .map(String.init)
            .map { token in
                switch token {
                case "INBOX":
                    return .inbox
                case "SENT":
                    return .sent
                case "DRAFT":
                    return .drafts
                case "TRASH":
                    return .trash
                case "SPAM":
                    return .spam
                case "ARCHIVE":
                    return .archive
                case "STARRED":
                    return .starred
                default:
                    return .userDefined(id: token, name: nil, kind: .label)
                }
            }
    }

    private func contains(_ value: String?, _ text: String) -> Bool {
        value?.localizedCaseInsensitiveContains(text) == true
    }

    private func matchesQuery(_ value: String) -> Bool {
        guard let text = query.text?.lowercased(), !text.isEmpty else { return true }
        if contains(value, text) { return true }
        let lowered = value.lowercased()
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return !tokens.isEmpty && tokens.allSatisfy { lowered.contains($0) }
    }

    private func excerpt(_ value: String, around text: String?) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        guard let text,
              let range = trimmed.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(trimmed.prefix(180))
        }
        let lowerBound = trimmed.index(range.lowerBound, offsetBy: -60, limitedBy: trimmed.startIndex) ?? trimmed.startIndex
        let upperBound = trimmed.index(range.upperBound, offsetBy: 100, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
        return String(trimmed[lowerBound..<upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ResultKey: Hashable {
    let accountID: String
    let threadID: String
}
