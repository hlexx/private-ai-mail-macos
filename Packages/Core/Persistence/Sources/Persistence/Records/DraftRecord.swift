import Foundation
import GRDB

public struct DraftRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "draft"

    public var id: String
    public var accountId: String
    public var provider: String
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
    public var rfcMessageId: String?
    public var rfcInReplyTo: String?
    public var rfcReferencesJson: String
    public var createdAt: Int
    public var updatedAt: Int

    public init(
        id: String,
        accountId: String,
        provider: String,
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
        rfcMessageId: String? = nil,
        rfcInReplyTo: String? = nil,
        rfcReferencesJson: String = "[]",
        createdAt: Int,
        updatedAt: Int
    ) {
        self.id = id
        self.accountId = accountId
        self.provider = provider
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
        self.rfcMessageId = rfcMessageId
        self.rfcInReplyTo = rfcInReplyTo
        self.rfcReferencesJson = rfcReferencesJson
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case provider
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
        case rfcMessageId = "rfc_message_id"
        case rfcInReplyTo = "rfc_in_reply_to"
        case rfcReferencesJson = "rfc_references_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
