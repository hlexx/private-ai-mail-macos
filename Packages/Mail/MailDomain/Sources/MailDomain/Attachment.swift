import Foundation

public enum AttachmentDisposition: String, Codable, Sendable, Equatable {
    case attachment
    case inline
}

public struct AttachmentByteFetchHandle: Codable, Sendable, Equatable {
    public let provider: MailProviderIdentifier
    public let accountId: String
    public let messageId: String
    public let attachmentId: String

    public init(provider: MailProviderIdentifier, accountId: String, messageId: String, attachmentId: String) {
        self.provider = provider
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
    }
}

public struct Attachment: Sendable, Equatable, Identifiable {
    public let id: String
    public let messageId: String
    public let accountId: String?
    public let filename: String?
    public let mimeType: String?
    public let sizeBytes: Int?
    public let contentId: String?
    public let disposition: AttachmentDisposition?
    public let byteFetchHandle: AttachmentByteFetchHandle?
    public let inlineData: String?

    public init(
        id: String,
        messageId: String,
        accountId: String? = nil,
        filename: String? = nil,
        mimeType: String? = nil,
        sizeBytes: Int? = nil,
        contentId: String? = nil,
        disposition: AttachmentDisposition? = nil,
        byteFetchHandle: AttachmentByteFetchHandle? = nil,
        inlineData: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.accountId = accountId
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentId = contentId
        self.disposition = disposition
        self.byteFetchHandle = byteFetchHandle
        self.inlineData = inlineData
    }
}
