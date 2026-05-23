public struct AttachmentPreviewRequest: Equatable, Sendable {
    public let attachmentId: String
    public let attachment: AttachmentInfo

    public init(attachmentId: String, attachment: AttachmentInfo) {
        self.attachmentId = attachmentId
        self.attachment = attachment
    }

    public init(attachment: AttachmentInfo) {
        self.init(attachmentId: attachment.id, attachment: attachment)
    }
}

public typealias AttachmentPreviewHandler = (AttachmentPreviewRequest) -> Void
