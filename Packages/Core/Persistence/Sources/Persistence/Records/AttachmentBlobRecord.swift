import Foundation
import GRDB

public struct AttachmentBlobRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_blob"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var relativePath: String
    public var byteCount: Int
    public var sha256: String
    public var storedAt: Int

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        relativePath: String,
        byteCount: Int,
        sha256: String,
        storedAt: Int
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.storedAt = storedAt
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case relativePath = "relative_path"
        case byteCount = "byte_count"
        case sha256
        case storedAt = "stored_at"
    }
}
