import Foundation
import GRDB

public struct AttachmentChunkRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_chunk"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: String
    public var chunkIndex: Int
    public var sourceOffset: Int
    public var text: String
    public var tokenCount: Int

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        extractionVersion: String,
        chunkIndex: Int,
        sourceOffset: Int,
        text: String,
        tokenCount: Int = 0
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
        self.chunkIndex = chunkIndex
        self.sourceOffset = sourceOffset
        self.text = text
        self.tokenCount = tokenCount
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case extractionVersion = "extraction_version"
        case chunkIndex = "chunk_index"
        case sourceOffset = "source_offset"
        case text
        case tokenCount = "token_count"
    }
}
