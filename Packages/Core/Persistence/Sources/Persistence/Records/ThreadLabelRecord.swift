import Foundation
import GRDB

public struct ThreadLabelRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "thread_label"

    public var threadId: String
    public var labelId: String

    public init(threadId: String, labelId: String) {
        self.threadId = threadId
        self.labelId = labelId
    }

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case labelId = "label_id"
    }
}
