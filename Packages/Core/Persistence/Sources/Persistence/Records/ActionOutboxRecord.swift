import Foundation
import GRDB

public struct ActionOutboxRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "action_outbox"

    public var opId: String
    public var accountId: String
    public var targetKind: String
    public var threadId: String?
    public var messageId: String?
    public var attachmentId: String?
    public var destinationKind: String?
    public var destinationId: String?
    public var actionKind: String
    public var actionSchemaVersion: Int
    public var idempotencyKey: String
    public var approvalRequirement: String
    public var approvalState: String
    public var status: String
    public var payloadJSON: String
    public var resultJSON: String?
    public var externalResultId: String?
    public var lastErrorKind: String?
    public var lastErrorCode: String?
    public var attemptCount: Int
    public var createdAt: Int
    public var updatedAt: Int
    public var approvedAt: Int?
    public var completedAt: Int?

    public init(
        opId: String,
        accountId: String,
        targetKind: String,
        threadId: String? = nil,
        messageId: String? = nil,
        attachmentId: String? = nil,
        destinationKind: String? = nil,
        destinationId: String? = nil,
        actionKind: String,
        actionSchemaVersion: Int,
        idempotencyKey: String,
        approvalRequirement: String,
        approvalState: String,
        status: String,
        payloadJSON: String,
        resultJSON: String? = nil,
        externalResultId: String? = nil,
        lastErrorKind: String? = nil,
        lastErrorCode: String? = nil,
        attemptCount: Int = 0,
        createdAt: Int,
        updatedAt: Int,
        approvedAt: Int? = nil,
        completedAt: Int? = nil
    ) {
        self.opId = opId
        self.accountId = accountId
        self.targetKind = targetKind
        self.threadId = threadId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.destinationKind = destinationKind
        self.destinationId = destinationId
        self.actionKind = actionKind
        self.actionSchemaVersion = actionSchemaVersion
        self.idempotencyKey = idempotencyKey
        self.approvalRequirement = approvalRequirement
        self.approvalState = approvalState
        self.status = status
        self.payloadJSON = payloadJSON
        self.resultJSON = resultJSON
        self.externalResultId = externalResultId
        self.lastErrorKind = lastErrorKind
        self.lastErrorCode = lastErrorCode
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.approvedAt = approvedAt
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case opId = "op_id"
        case accountId = "account_id"
        case targetKind = "target_kind"
        case threadId = "thread_id"
        case messageId = "message_id"
        case attachmentId = "attachment_id"
        case destinationKind = "destination_kind"
        case destinationId = "destination_id"
        case actionKind = "action_kind"
        case actionSchemaVersion = "action_schema_version"
        case idempotencyKey = "idempotency_key"
        case approvalRequirement = "approval_requirement"
        case approvalState = "approval_state"
        case status
        case payloadJSON = "payload_json"
        case resultJSON = "result_json"
        case externalResultId = "external_result_id"
        case lastErrorKind = "last_error_kind"
        case lastErrorCode = "last_error_code"
        case attemptCount = "attempt_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case approvedAt = "approved_at"
        case completedAt = "completed_at"
    }
}
