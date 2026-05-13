import Foundation
import GRDB

public struct SyncStateRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sync_state"

    public var accountId: String
    public var historyId: String?
    public var lastBootstrapAt: Int?
    public var status: String

    public init(accountId: String, historyId: String? = nil, lastBootstrapAt: Int? = nil, status: String = "idle") {
        self.accountId = accountId
        self.historyId = historyId
        self.lastBootstrapAt = lastBootstrapAt
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case historyId = "history_id"
        case lastBootstrapAt = "last_bootstrap_at"
        case status
    }
}
