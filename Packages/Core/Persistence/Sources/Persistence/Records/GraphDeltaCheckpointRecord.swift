import Foundation
import GRDB

public struct GraphDeltaCheckpointRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "graph_delta_checkpoint"

    public var accountId: String
    public var folderId: String
    public var deltaURL: String
    public var updatedAt: Int

    public init(accountId: String, folderId: String, deltaURL: String, updatedAt: Int) {
        self.accountId = accountId
        self.folderId = folderId
        self.deltaURL = deltaURL
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case folderId = "folder_id"
        case deltaURL = "delta_url"
        case updatedAt = "updated_at"
    }
}
