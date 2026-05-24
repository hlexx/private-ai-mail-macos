import Foundation
import GRDB

public struct AttachmentAIArtifactRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_ai_artifact"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var taskId: String
    public var promptVersion: String
    public var schemaVersion: String
    public var modelId: String
    public var extractionVersion: String
    public var inputFingerprint: String
    public var contentJSON: String
    public var generatedAt: Int

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        taskId: String,
        promptVersion: String,
        schemaVersion: String,
        modelId: String,
        extractionVersion: String,
        inputFingerprint: String,
        contentJSON: String,
        generatedAt: Int
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.taskId = taskId
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.modelId = modelId
        self.extractionVersion = extractionVersion
        self.inputFingerprint = inputFingerprint
        self.contentJSON = contentJSON
        self.generatedAt = generatedAt
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case taskId = "task_id"
        case promptVersion = "prompt_version"
        case schemaVersion = "schema_version"
        case modelId = "model_id"
        case extractionVersion = "extraction_version"
        case inputFingerprint = "input_fingerprint"
        case contentJSON = "content_json"
        case generatedAt = "generated_at"
    }
}
