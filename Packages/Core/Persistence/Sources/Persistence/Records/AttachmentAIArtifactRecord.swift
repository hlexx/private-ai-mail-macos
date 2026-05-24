import Foundation
import GRDB

public struct AttachmentAIArtifactRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_ai_artifact"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: String
    public var artifactKind: String
    public var artifactVersion: Int
    public var modelId: String?
    public var contentHash: String?
    public var payloadJSON: String
    public var createdAt: Int
    public var updatedAt: Int

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        extractionVersion: String,
        artifactKind: String,
        artifactVersion: Int,
        modelId: String?,
        contentHash: String?,
        payloadJSON: String,
        createdAt: Int,
        updatedAt: Int
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
        self.artifactKind = artifactKind
        self.artifactVersion = artifactVersion
        self.modelId = modelId
        self.contentHash = contentHash
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case extractionVersion = "extraction_version"
        case artifactKind = "artifact_kind"
        case artifactVersion = "artifact_version"
        case modelId = "model_id"
        case contentHash = "content_hash"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
