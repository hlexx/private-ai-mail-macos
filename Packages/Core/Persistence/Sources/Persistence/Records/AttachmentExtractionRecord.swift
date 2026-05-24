import Foundation
import GRDB

public struct AttachmentExtractionRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_extraction"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: String
    public var status: String
    public var contentHash: String?
    public var mime: String?
    public var filename: String?
    public var byteCount: Int?
    public var createdAt: Int
    public var updatedAt: Int
    public var completedAt: Int?
    public var errorCode: String?
    public var errorMessage: String?

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        extractionVersion: String,
        status: String,
        contentHash: String?,
        mime: String?,
        filename: String?,
        byteCount: Int?,
        createdAt: Int,
        updatedAt: Int,
        completedAt: Int?,
        errorCode: String?,
        errorMessage: String?
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
        self.status = status
        self.contentHash = contentHash
        self.mime = mime
        self.filename = filename
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case extractionVersion = "extraction_version"
        case status
        case contentHash = "content_hash"
        case mime, filename
        case byteCount = "byte_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}
