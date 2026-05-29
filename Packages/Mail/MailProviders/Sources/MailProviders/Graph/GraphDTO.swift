import Foundation

public enum GraphDTO {
    public struct CollectionResponse<Value: Codable & Sendable>: Codable, Sendable {
        public let value: [Value]
        public let nextLink: String?
        public let deltaLink: String?

        public init(value: [Value], nextLink: String? = nil, deltaLink: String? = nil) {
            self.value = value
            self.nextLink = nextLink
            self.deltaLink = deltaLink
        }

        private enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
            case deltaLink = "@odata.deltaLink"
        }
    }

    public typealias MailFolderList = CollectionResponse<MailFolder>
    public typealias MessageDeltaResponse = CollectionResponse<Message>
    public typealias AttachmentList = CollectionResponse<AttachmentMetadata>

    public struct MailFolder: Codable, Sendable, Equatable {
        public let id: String
        public let displayName: String
        public let parentFolderId: String?
        public let childFolderCount: Int?
        public let unreadItemCount: Int?
        public let totalItemCount: Int?

        public init(
            id: String,
            displayName: String,
            parentFolderId: String? = nil,
            childFolderCount: Int? = nil,
            unreadItemCount: Int? = nil,
            totalItemCount: Int? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.parentFolderId = parentFolderId
            self.childFolderCount = childFolderCount
            self.unreadItemCount = unreadItemCount
            self.totalItemCount = totalItemCount
        }
    }

    public struct Message: Codable, Sendable, Equatable {
        public let id: String?
        public let changeKey: String?
        public let internetMessageId: String?
        public let conversationId: String?
        public let parentFolderId: String?
        public let subject: String?
        public let bodyPreview: String?
        public let body: ItemBody?
        public let from: Recipient?
        public let sender: Recipient?
        public let toRecipients: [Recipient]?
        public let ccRecipients: [Recipient]?
        public let bccRecipients: [Recipient]?
        public let replyTo: [Recipient]?
        public let receivedDateTime: String?
        public let sentDateTime: String?
        public let isRead: Bool?
        public let isDraft: Bool?
        public let hasAttachments: Bool?
        public let attachments: [AttachmentMetadata]?
        public let categories: [String]?
        public let flag: FollowupFlag?
        public let deletedReason: String?
        public let odataType: String?
        public let odataRemoved: Removed?

        public init(
            id: String? = nil,
            changeKey: String? = nil,
            internetMessageId: String? = nil,
            conversationId: String? = nil,
            parentFolderId: String? = nil,
            subject: String? = nil,
            bodyPreview: String? = nil,
            body: ItemBody? = nil,
            from: Recipient? = nil,
            sender: Recipient? = nil,
            toRecipients: [Recipient]? = nil,
            ccRecipients: [Recipient]? = nil,
            bccRecipients: [Recipient]? = nil,
            replyTo: [Recipient]? = nil,
            receivedDateTime: String? = nil,
            sentDateTime: String? = nil,
            isRead: Bool? = nil,
            isDraft: Bool? = nil,
            hasAttachments: Bool? = nil,
            attachments: [AttachmentMetadata]? = nil,
            categories: [String]? = nil,
            flag: FollowupFlag? = nil,
            deletedReason: String? = nil,
            odataType: String? = nil,
            odataRemoved: Removed? = nil
        ) {
            self.id = id
            self.changeKey = changeKey
            self.internetMessageId = internetMessageId
            self.conversationId = conversationId
            self.parentFolderId = parentFolderId
            self.subject = subject
            self.bodyPreview = bodyPreview
            self.body = body
            self.from = from
            self.sender = sender
            self.toRecipients = toRecipients
            self.ccRecipients = ccRecipients
            self.bccRecipients = bccRecipients
            self.replyTo = replyTo
            self.receivedDateTime = receivedDateTime
            self.sentDateTime = sentDateTime
            self.isRead = isRead
            self.isDraft = isDraft
            self.hasAttachments = hasAttachments
            self.attachments = attachments
            self.categories = categories
            self.flag = flag
            self.deletedReason = deletedReason
            self.odataType = odataType
            self.odataRemoved = odataRemoved
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case changeKey
            case internetMessageId
            case conversationId
            case parentFolderId
            case subject
            case bodyPreview
            case body
            case from
            case sender
            case toRecipients
            case ccRecipients
            case bccRecipients
            case replyTo
            case receivedDateTime
            case sentDateTime
            case isRead
            case isDraft
            case hasAttachments
            case attachments
            case categories
            case flag
            case deletedReason
            case odataType = "@odata.type"
            case odataRemoved = "@removed"
        }
    }

    public struct EmailAddress: Codable, Sendable, Equatable {
        public let name: String?
        public let address: String?

        public init(name: String? = nil, address: String? = nil) {
            self.name = name
            self.address = address
        }
    }

    public struct Recipient: Codable, Sendable, Equatable {
        public let emailAddress: EmailAddress

        public init(emailAddress: EmailAddress) {
            self.emailAddress = emailAddress
        }
    }

    public enum BodyContentType: String, Codable, Sendable {
        case text
        case html
    }

    public struct ItemBody: Codable, Sendable, Equatable {
        public let contentType: BodyContentType?
        public let content: String?

        public init(contentType: BodyContentType? = nil, content: String? = nil) {
            self.contentType = contentType
            self.content = content
        }
    }

    public struct AttachmentMetadata: Codable, Sendable, Equatable {
        public let id: String?
        public let name: String?
        public let contentType: String?
        public let size: Int?
        public let isInline: Bool?
        public let contentId: String?
        public let lastModifiedDateTime: String?
        public let odataType: String?

        public init(
            id: String? = nil,
            name: String? = nil,
            contentType: String? = nil,
            size: Int? = nil,
            isInline: Bool? = nil,
            contentId: String? = nil,
            lastModifiedDateTime: String? = nil,
            odataType: String? = nil
        ) {
            self.id = id
            self.name = name
            self.contentType = contentType
            self.size = size
            self.isInline = isInline
            self.contentId = contentId
            self.lastModifiedDateTime = lastModifiedDateTime
            self.odataType = odataType
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case contentType
            case size
            case isInline
            case contentId
            case lastModifiedDateTime
            case odataType = "@odata.type"
        }
    }

    public struct AttachmentContent: Codable, Sendable, Equatable {
        public let id: String?
        public let name: String?
        public let contentType: String?
        public let size: Int?
        public let isInline: Bool?
        public let contentId: String?
        public let contentBytes: String?
        public let odataType: String?

        public init(
            id: String? = nil,
            name: String? = nil,
            contentType: String? = nil,
            size: Int? = nil,
            isInline: Bool? = nil,
            contentId: String? = nil,
            contentBytes: String? = nil,
            odataType: String? = nil
        ) {
            self.id = id
            self.name = name
            self.contentType = contentType
            self.size = size
            self.isInline = isInline
            self.contentId = contentId
            self.contentBytes = contentBytes
            self.odataType = odataType
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case contentType
            case size
            case isInline
            case contentId
            case contentBytes
            case odataType = "@odata.type"
        }
    }

    public struct FollowupFlag: Codable, Sendable, Equatable {
        public let flagStatus: String?

        public init(flagStatus: String? = nil) {
            self.flagStatus = flagStatus
        }
    }

    public struct Removed: Codable, Sendable, Equatable {
        public let reason: String?

        public init(reason: String? = nil) {
            self.reason = reason
        }
    }

    public struct ErrorResponse: Codable, Sendable, Equatable {
        public let error: ErrorPayload

        public init(error: ErrorPayload) {
            self.error = error
        }
    }

    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let code: String?
        public let message: String?
        public let innerError: InnerError?

        public init(code: String? = nil, message: String? = nil, innerError: InnerError? = nil) {
            self.code = code
            self.message = message
            self.innerError = innerError
        }
    }

    public struct InnerError: Codable, Sendable, Equatable {
        public let code: String?
        public let date: String?
        public let requestId: String?
        public let clientRequestId: String?

        public init(code: String? = nil, date: String? = nil, requestId: String? = nil, clientRequestId: String? = nil) {
            self.code = code
            self.date = date
            self.requestId = requestId
            self.clientRequestId = clientRequestId
        }

        private enum CodingKeys: String, CodingKey {
            case code
            case date
            case requestId = "request-id"
            case clientRequestId = "client-request-id"
        }
    }

    public struct SendMailRequest: Codable, Sendable, Equatable {
        public let message: Message
        public let saveToSentItems: Bool

        public init(message: Message, saveToSentItems: Bool = true) {
            self.message = message
            self.saveToSentItems = saveToSentItems
        }
    }

    public struct SendResult: Codable, Sendable, Equatable {
        public let accepted: Bool
        public let statusCode: Int
        public let requestId: String?

        public init(accepted: Bool, statusCode: Int, requestId: String? = nil) {
            self.accepted = accepted
            self.statusCode = statusCode
            self.requestId = requestId
        }
    }
}
