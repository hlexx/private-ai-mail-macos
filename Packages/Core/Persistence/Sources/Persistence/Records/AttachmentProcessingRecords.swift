import Foundation
import GRDB

public struct AttachmentExtractionRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_extraction"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: Int
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
        extractionVersion: Int,
        status: String,
        contentHash: String? = nil,
        mime: String? = nil,
        filename: String? = nil,
        byteCount: Int? = nil,
        createdAt: Int,
        updatedAt: Int,
        completedAt: Int? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
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

public struct AttachmentChunkRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_chunk"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: Int
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
        extractionVersion: Int,
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

public struct AttachmentAIArtifactRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_ai_artifact"

    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: Int
    public var artifactKind: String
    public var artifactVersion: Int
    public var modelId: String?
    public var contentHash: String?
    public var payloadJson: String
    public var createdAt: Int
    public var updatedAt: Int

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        extractionVersion: Int,
        artifactKind: String,
        artifactVersion: Int,
        modelId: String? = nil,
        contentHash: String? = nil,
        payloadJson: String,
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
        self.payloadJson = payloadJson
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
        case payloadJson = "payload_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct AttachmentProcessingJobRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachment_processing_job"

    public var id: String
    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var jobKind: String
    public var status: String
    public var priority: Int
    public var attemptCount: Int
    public var availableAt: Int
    public var createdAt: Int
    public var updatedAt: Int
    public var lastErrorCode: String?
    public var lastErrorMessage: String?

    public init(
        id: String,
        accountId: String,
        messageId: String,
        attachmentId: String,
        jobKind: String,
        status: String,
        priority: Int = 0,
        attemptCount: Int = 0,
        availableAt: Int,
        createdAt: Int,
        updatedAt: Int,
        lastErrorCode: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.jobKind = jobKind
        self.status = status
        self.priority = priority
        self.attemptCount = attemptCount
        self.availableAt = availableAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case jobKind = "job_kind"
        case status, priority
        case attemptCount = "attempt_count"
        case availableAt = "available_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastErrorCode = "last_error_code"
        case lastErrorMessage = "last_error_message"
    }
}
