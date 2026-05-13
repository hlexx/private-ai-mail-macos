import Foundation

public struct Attachment: Sendable, Equatable, Identifiable {
    public let id: String
    public let messageId: String
    public let filename: String?
    public let mimeType: String?
    public let sizeBytes: Int?

    public init(
        id: String,
        messageId: String,
        filename: String? = nil,
        mimeType: String? = nil,
        sizeBytes: Int? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}
