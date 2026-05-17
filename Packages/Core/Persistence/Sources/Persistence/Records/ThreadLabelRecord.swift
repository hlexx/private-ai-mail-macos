import Foundation
import GRDB

public struct ThreadLabelRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "thread_label"

    public var accountId: String
    public var threadId: String
    public var labelId: String

    public init(accountId: String, threadId: String, labelId: String) {
        self.accountId = accountId
        self.threadId = threadId
        self.labelId = labelId
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case threadId = "thread_id"
        case labelId = "label_id"
    }
}
