import Foundation
import GRDB

public struct AttachmentRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment"

    public var id: String
    public var messageId: String
    public var accountId: String
    public var filename: String?
    public var mime: String?
    public var sizeBytes: Int?
    public var contentId: String?
    public var dataBase64: String?

    public init(
        id: String,
        messageId: String,
        accountId: String,
        filename: String? = nil,
        mime: String? = nil,
        sizeBytes: Int? = nil,
        contentId: String? = nil,
        dataBase64: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.accountId = accountId
        self.filename = filename
        self.mime = mime
        self.sizeBytes = sizeBytes
        self.contentId = contentId
        self.dataBase64 = dataBase64
    }

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case accountId = "account_id"
        case filename, mime
        case sizeBytes = "size_bytes"
        case contentId = "content_id"
        case dataBase64 = "data_base64"
    }
}
