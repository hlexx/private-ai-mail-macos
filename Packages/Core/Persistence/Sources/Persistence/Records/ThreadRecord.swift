import Foundation
import GRDB

public struct ThreadRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "thread"

    public var id: String
    public var accountId: String
    public var subject: String?
    public var snippet: String?
    public var lastMessageAt: Int
    public var messageCount: Int
    public var hasUnread: Int

    public init(id: String, accountId: String, subject: String? = nil, snippet: String? = nil, lastMessageAt: Int, messageCount: Int = 0, hasUnread: Int = 0) {
        self.id = id
        self.accountId = accountId
        self.subject = subject
        self.snippet = snippet
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
        self.hasUnread = hasUnread
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case subject, snippet
        case lastMessageAt = "last_message_at"
        case messageCount = "message_count"
        case hasUnread = "has_unread"
    }
}
