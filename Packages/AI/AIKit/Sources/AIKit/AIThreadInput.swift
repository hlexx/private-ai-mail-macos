import Foundation

public struct AIThreadInput: Sendable {
    public let messages: [Message]
    public let attachments: [Attachment]

    public init(messages: [Message], attachments: [Attachment] = []) {
        self.messages = messages
        self.attachments = attachments
    }

    public struct Message: Sendable {
        public let from: String
        public let sentAt: Date
        public let bodyText: String

        public init(from: String, sentAt: Date, bodyText: String) {
            self.from = from
            self.sentAt = sentAt
            self.bodyText = bodyText
        }
    }

    public struct Attachment: Sendable {
        public let filename: String
        public let mime: String
        public let pageCount: Int?

        public init(filename: String, mime: String, pageCount: Int? = nil) {
            self.filename = filename
            self.mime = mime
            self.pageCount = pageCount
        }
    }
}
