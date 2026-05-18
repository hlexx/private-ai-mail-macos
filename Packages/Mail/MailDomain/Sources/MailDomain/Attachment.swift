import Foundation

public struct Attachment: Sendable, Equatable, Identifiable {
    public let id: String
    public let messageId: String
    public let filename: String?
    public let mimeType: String?
    public let sizeBytes: Int?
    public let contentId: String?
    public let inlineData: String?

    public init(
        id: String,
        messageId: String,
        filename: String? = nil,
        mimeType: String? = nil,
        sizeBytes: Int? = nil,
        contentId: String? = nil,
        inlineData: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentId = contentId
        self.inlineData = inlineData
    }
}
