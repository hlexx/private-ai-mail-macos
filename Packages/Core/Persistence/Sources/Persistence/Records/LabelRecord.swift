import Foundation
import GRDB

public struct LabelRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "label"
    public static let persistenceKeyColumns = ["account_id", "id"]

    public var id: String
    public var accountId: String
    public var name: String
    public var type: LabelType
    public var color: String?
    public var messagesUnreadCount: Int
    public var messagesTotalCount: Int

    public init(
        id: String,
        accountId: String,
        name: String,
        type: LabelType = .system,
        color: String? = nil,
        messagesUnreadCount: Int = 0,
        messagesTotalCount: Int = 0
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.type = type
        self.color = color
        self.messagesUnreadCount = messagesUnreadCount
        self.messagesTotalCount = messagesTotalCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case name, type, color
        case messagesUnreadCount = "messages_unread_count"
        case messagesTotalCount = "messages_total_count"
    }
}

public enum LabelType: String, Codable, Sendable {
    case system, user, category
}
