import Foundation
import GRDB

public struct AttachmentExtractionRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_extraction"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: String
    public var status: String
    public var mime: String
    public var text: String?
    public var unsupportedReason: String?
    public var generatedAt: Int

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        extractionVersion: String,
        status: String,
        mime: String,
        text: String?,
        unsupportedReason: String?,
        generatedAt: Int
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
        self.status = status
        self.mime = mime
        self.text = text
        self.unsupportedReason = unsupportedReason
        self.generatedAt = generatedAt
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case extractionVersion = "extraction_version"
        case status, mime, text
        case unsupportedReason = "unsupported_reason"
        case generatedAt = "generated_at"
    }
}
