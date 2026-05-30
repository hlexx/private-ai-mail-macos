import Foundation

public struct OutgoingMessage: Sendable, Equatable {
    public let from: Address
    public let to: [Address]
    public let cc: [Address]
    public let bcc: [Address]
    public let subject: String
    public let body: String
    public let inReplyTo: String?
    public let references: [String]
    public let messageIDSeed: String?
    public let messageIDHeader: String?

    public init(
        from: Address,
        to: [Address],
        cc: [Address] = [],
        bcc: [Address] = [],
        subject: String,
        body: String,
        inReplyTo: String? = nil,
        references: [String] = [],
        messageIDSeed: String? = nil,
        messageIDHeader: String? = nil
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.inReplyTo = inReplyTo
        self.references = references
        self.messageIDSeed = messageIDSeed
        self.messageIDHeader = messageIDHeader
    }
}
