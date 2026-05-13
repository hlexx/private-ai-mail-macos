import Foundation
import GRDB

public struct MessageRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "message"

    public var id: String
    public var threadId: String
    public var accountId: String
    public var messageIdHeader: String?
    public var fromAddr: String?
    public var toAddr: String?
    public var ccAddr: String?
    public var sentAt: Int
    public var snippet: String?
    public var bodyHtmlPath: String?
    public var bodyTextPath: String?
    public var flags: Int

    public init(id: String, threadId: String, accountId: String, messageIdHeader: String? = nil, fromAddr: String? = nil, toAddr: String? = nil, ccAddr: String? = nil, sentAt: Int, snippet: String? = nil, bodyHtmlPath: String? = nil, bodyTextPath: String? = nil, flags: Int = 0) {
        self.id = id
        self.threadId = threadId
        self.accountId = accountId
        self.messageIdHeader = messageIdHeader
        self.fromAddr = fromAddr
        self.toAddr = toAddr
        self.ccAddr = ccAddr
        self.sentAt = sentAt
        self.snippet = snippet
        self.bodyHtmlPath = bodyHtmlPath
        self.bodyTextPath = bodyTextPath
        self.flags = flags
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case accountId = "account_id"
        case messageIdHeader = "message_id_header"
        case fromAddr = "from_addr"
        case toAddr = "to_addr"
        case ccAddr = "cc_addr"
        case sentAt = "sent_at"
        case snippet
        case bodyHtmlPath = "body_html_path"
        case bodyTextPath = "body_text_path"
        case flags
    }
}
