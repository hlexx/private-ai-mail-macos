import Foundation
import GRDB

public struct SendQueueItemRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "send_queue_item"

    public var id: String
    public var draftId: String?
    public var accountId: String
    public var provider: String
    public var idempotencyKey: String
    public var status: String
    public var fromAddr: String
    public var toAddr: String
    public var ccAddr: String?
    public var bccAddr: String?
    public var subject: String
    public var bodyText: String?
    public var bodyHtml: String?
    public var bodyStorage: String
    public var threadId: String?
    public var replyToProviderMessageId: String?
    public var providerMessageId: String?
    public var providerThreadId: String?
    public var rfcMessageId: String?
    public var rfcInReplyTo: String?
    public var rfcReferencesJson: String
    public var attempts: Int
    public var maxAttempts: Int
    public var nextAttemptAt: Int?
    public var lastAttemptAt: Int?
    public var createdAt: Int
    public var updatedAt: Int
    public var sentAt: Int?
    public var sanitizedErrorCategory: String?
    public var sanitizedErrorCode: String?
    public var sanitizedErrorMessage: String?
    public var retryAfterSeconds: Int?

    public init(
        id: String,
        draftId: String? = nil,
        accountId: String,
        provider: String,
        idempotencyKey: String,
        status: String,
        fromAddr: String,
        toAddr: String,
        ccAddr: String? = nil,
        bccAddr: String? = nil,
        subject: String,
        bodyText: String? = nil,
        bodyHtml: String? = nil,
        bodyStorage: String = "sqlite",
        threadId: String? = nil,
        replyToProviderMessageId: String? = nil,
        providerMessageId: String? = nil,
        providerThreadId: String? = nil,
        rfcMessageId: String? = nil,
        rfcInReplyTo: String? = nil,
        rfcReferencesJson: String = "[]",
        attempts: Int = 0,
        maxAttempts: Int = 5,
        nextAttemptAt: Int? = nil,
        lastAttemptAt: Int? = nil,
        createdAt: Int,
        updatedAt: Int,
        sentAt: Int? = nil,
        sanitizedErrorCategory: String? = nil,
        sanitizedErrorCode: String? = nil,
        sanitizedErrorMessage: String? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.id = id
        self.draftId = draftId
        self.accountId = accountId
        self.provider = provider
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.fromAddr = fromAddr
        self.toAddr = toAddr
        self.ccAddr = ccAddr
        self.bccAddr = bccAddr
        self.subject = subject
        self.bodyText = bodyText
        self.bodyHtml = bodyHtml
        self.bodyStorage = bodyStorage
        self.threadId = threadId
        self.replyToProviderMessageId = replyToProviderMessageId
        self.providerMessageId = providerMessageId
        self.providerThreadId = providerThreadId
        self.rfcMessageId = rfcMessageId
        self.rfcInReplyTo = rfcInReplyTo
        self.rfcReferencesJson = rfcReferencesJson
        self.attempts = attempts
        self.maxAttempts = maxAttempts
        self.nextAttemptAt = nextAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sentAt = sentAt
        self.sanitizedErrorCategory = sanitizedErrorCategory
        self.sanitizedErrorCode = sanitizedErrorCode
        self.sanitizedErrorMessage = sanitizedErrorMessage
        self.retryAfterSeconds = retryAfterSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id
        case draftId = "draft_id"
        case accountId = "account_id"
        case provider
        case idempotencyKey = "idempotency_key"
        case status
        case fromAddr = "from_addr"
        case toAddr = "to_addr"
        case ccAddr = "cc_addr"
        case bccAddr = "bcc_addr"
        case subject
        case bodyText = "body_text"
        case bodyHtml = "body_html"
        case bodyStorage = "body_storage"
        case threadId = "thread_id"
        case replyToProviderMessageId = "reply_to_provider_message_id"
        case providerMessageId = "provider_message_id"
        case providerThreadId = "provider_thread_id"
        case rfcMessageId = "rfc_message_id"
        case rfcInReplyTo = "rfc_in_reply_to"
        case rfcReferencesJson = "rfc_references_json"
        case attempts
        case maxAttempts = "max_attempts"
        case nextAttemptAt = "next_attempt_at"
        case lastAttemptAt = "last_attempt_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sentAt = "sent_at"
        case sanitizedErrorCategory = "sanitized_error_category"
        case sanitizedErrorCode = "sanitized_error_code"
        case sanitizedErrorMessage = "sanitized_error_message"
        case retryAfterSeconds = "retry_after_seconds"
    }
}
