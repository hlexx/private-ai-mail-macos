import Foundation

public struct Message: Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String
    public let accountId: String
    public let messageIdHeader: String?
    public let from: Address?
    public let to: [Address]
    public let cc: [Address]
    public let sentAt: Date
    public let snippet: String?
    public let bodyText: String?
    public let bodyHTML: String?
    public let attachments: [Attachment]
    public let isUnread: Bool
    public let isSentByMe: Bool

    public init(
        id: String,
        threadId: String,
        accountId: String,
        messageIdHeader: String? = nil,
        from: Address? = nil,
        to: [Address] = [],
        cc: [Address] = [],
        sentAt: Date,
        snippet: String? = nil,
        bodyText: String? = nil,
        bodyHTML: String? = nil,
        attachments: [Attachment] = [],
        isUnread: Bool = false,
        isSentByMe: Bool = false
    ) {
        self.id = id
        self.threadId = threadId
        self.accountId = accountId
        self.messageIdHeader = messageIdHeader
        self.from = from
        self.to = to
        self.cc = cc
        self.sentAt = sentAt
        self.snippet = snippet
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.attachments = attachments
        self.isUnread = isUnread
        self.isSentByMe = isSentByMe
    }
}
