import Foundation
import GRDB

public struct AttachmentChunkRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_chunk"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: String
    public var chunkIndex: Int
    public var contentText: String
    public var sourceReference: String?
    public var pageNumber: Int?
    public var sourceStart: Int?
    public var sourceEnd: Int?
    public var tokenCount: Int?
    public var createdAt: Int

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        extractionVersion: String,
        chunkIndex: Int,
        contentText: String,
        sourceReference: String? = nil,
        pageNumber: Int? = nil,
        sourceStart: Int? = nil,
        sourceEnd: Int? = nil,
        tokenCount: Int? = nil,
        createdAt: Int
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
        self.chunkIndex = chunkIndex
        self.contentText = contentText
        self.sourceReference = sourceReference
        self.pageNumber = pageNumber
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.tokenCount = tokenCount
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case extractionVersion = "extraction_version"
        case chunkIndex = "chunk_index"
        case contentText = "content_text"
        case sourceReference = "source_reference"
        case pageNumber = "page_number"
        case sourceStart = "source_start"
        case sourceEnd = "source_end"
        case tokenCount = "token_count"
        case createdAt = "created_at"
    }
}
