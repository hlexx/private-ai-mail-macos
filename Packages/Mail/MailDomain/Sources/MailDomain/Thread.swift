import Foundation

public struct Thread: Sendable, Equatable, Identifiable {
    public let id: String
    public let accountId: String
    public let subject: String?
    public let snippet: String?
    public let lastMessageAt: Date
    public let messageCount: Int
    public let hasUnread: Bool
    public let messages: [Message]

    public init(
        id: String,
        accountId: String,
        subject: String? = nil,
        snippet: String? = nil,
        lastMessageAt: Date,
        messageCount: Int = 0,
        hasUnread: Bool = false,
        messages: [Message] = []
    ) {
        self.id = id
        self.accountId = accountId
        self.subject = subject
        self.snippet = snippet
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
        self.hasUnread = hasUnread
        self.messages = messages
    }
}
