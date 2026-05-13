import Foundation
import GRDB

public struct AccountRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "account"

    public var id: String
    public var provider: String
    public var email: String
    public var displayName: String?
    public var createdAt: Int
    public var lastSyncedAt: Int?

    public init(id: String, provider: String = "gmail", email: String, displayName: String? = nil, createdAt: Int, lastSyncedAt: Int? = nil) {
        self.id = id
        self.provider = provider
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, email
        case displayName = "display_name"
        case createdAt = "created_at"
        case lastSyncedAt = "last_synced_at"
    }
}
