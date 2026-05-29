import Foundation
import MailDomain

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
        attachmentMIMETypes: Set<String> = []
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
           !attachmentFilenames.isEmpty || !attachmentMIMETypes.isEmpty {
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
        self.text = normalizedText?.isEmpty == false ? normalizedText : nil
        self.filters = filters
        self.mode = mode
        self.sort = sort
        self.limit = max(1, limit)
        self.offset = max(0, offset)
        try filters.validate()
    }

    public var redactedDescription: String {
        let textDescription = text.map { "<redacted:\($0.count) chars>" } ?? "none"
        return "MailSearchQuery(text=\(textDescription),mode=\(mode),sort=\(sort),limit=\(limit),offset=\(offset),filters={\(filters.redactedDescription)})"
    }

    public var description: String {
        redactedDescription
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
    public var id: String { threadID }

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

    public init(
        query: MailSearchQuery,
        results: [MailSearchResult],
        localResultsComplete: Bool = true,
        totalResultCount: Int? = nil
    ) {
        self.query = query
        self.results = results
        self.localResultsComplete = localResultsComplete
        self.totalResultCount = totalResultCount
    }
}

public struct MailIndexedAttachment: Sendable, Equatable {
    public let filename: String?
    public let mime: String?

    public init(filename: String? = nil, mime: String? = nil) {
        self.filename = filename
        self.mime = mime
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
