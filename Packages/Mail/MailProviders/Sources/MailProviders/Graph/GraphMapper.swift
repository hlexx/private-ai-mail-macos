import Foundation
import MailDomain

public struct GraphMappedFolder: Sendable, Equatable {
    public let id: String
    public let accountId: String
    public let providerFolderId: String
    public let parentProviderFolderId: String?
    public let displayName: String
    public let mailbox: CanonicalMailbox
    public let unreadCount: Int?
    public let totalCount: Int?

    public init(
        id: String,
        accountId: String,
        providerFolderId: String,
        parentProviderFolderId: String? = nil,
        displayName: String,
        mailbox: CanonicalMailbox,
        unreadCount: Int? = nil,
        totalCount: Int? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.providerFolderId = providerFolderId
        self.parentProviderFolderId = parentProviderFolderId
        self.displayName = displayName
        self.mailbox = mailbox
        self.unreadCount = unreadCount
        self.totalCount = totalCount
    }
}

public struct GraphMappedMessage: Sendable, Equatable {
    public let message: MailDomain.Message
    public let providerMessageId: String
    public let providerConversationId: String?
    public let providerParentFolderId: String?
    public let mailbox: CanonicalMailbox?
    public let categories: [String]
    public let categoryMailboxes: [CanonicalMailbox]
    public let isFlagged: Bool
    public let isInTrash: Bool

    public init(
        message: MailDomain.Message,
        providerMessageId: String,
        providerConversationId: String? = nil,
        providerParentFolderId: String? = nil,
        mailbox: CanonicalMailbox? = nil,
        categories: [String] = [],
        categoryMailboxes: [CanonicalMailbox] = [],
        isFlagged: Bool = false,
        isInTrash: Bool = false
    ) {
        self.message = message
        self.providerMessageId = providerMessageId
        self.providerConversationId = providerConversationId
        self.providerParentFolderId = providerParentFolderId
        self.mailbox = mailbox
        self.categories = categories
        self.categoryMailboxes = categoryMailboxes
        self.isFlagged = isFlagged
        self.isInTrash = isInTrash
    }
}

public struct GraphRemovedMessage: Sendable, Equatable {
    public let id: String
    public let accountId: String
    public let providerMessageId: String
    public let providerParentFolderId: String?
    public let reason: String?
    public let isDeleted: Bool
    public let isMoved: Bool

    public init(
        id: String,
        accountId: String,
        providerMessageId: String,
        providerParentFolderId: String? = nil,
        reason: String? = nil,
        isDeleted: Bool,
        isMoved: Bool
    ) {
        self.id = id
        self.accountId = accountId
        self.providerMessageId = providerMessageId
        self.providerParentFolderId = providerParentFolderId
        self.reason = reason
        self.isDeleted = isDeleted
        self.isMoved = isMoved
    }
}

public enum GraphMappedMessageChange: Sendable, Equatable {
    case upsert(GraphMappedMessage)
    case removed(GraphRemovedMessage)
}

public enum GraphMapper {
    public static func scopedExternalId(accountId: String, kind: String, providerId: String) -> String {
        "\(MailProviderIdentifier.outlook.rawValue):\(accountId):\(kind):\(providerId)"
    }

    public static func mapFolder(_ dto: GraphDTO.MailFolder, accountId: String) -> GraphMappedFolder {
        let id = scopedExternalId(accountId: accountId, kind: "folder", providerId: dto.id)
        let mailbox = canonicalMailbox(forFolderName: dto.displayName, folderId: id)
        return GraphMappedFolder(
            id: id,
            accountId: accountId,
            providerFolderId: dto.id,
            parentProviderFolderId: dto.parentFolderId,
            displayName: dto.displayName,
            mailbox: mailbox,
            unreadCount: dto.unreadItemCount,
            totalCount: dto.totalItemCount
        )
    }

    public static func mapMessageChange(
        _ dto: GraphDTO.Message,
        accountId: String,
        foldersById: [String: GraphDTO.MailFolder] = [:]
    ) -> GraphMappedMessageChange? {
        guard let providerMessageId = dto.id else { return nil }
        let reason = dto.odataRemoved?.reason ?? dto.deletedReason
        if dto.odataRemoved != nil || dto.deletedReason != nil {
            return .removed(mapRemovedMessage(
                providerMessageId: providerMessageId,
                accountId: accountId,
                providerParentFolderId: dto.parentFolderId,
                reason: reason
            ))
        }
        guard let mapped = mapMessage(dto, accountId: accountId, foldersById: foldersById) else {
            return nil
        }
        return .upsert(mapped)
    }

    public static func mapMessage(
        _ dto: GraphDTO.Message,
        accountId: String,
        foldersById: [String: GraphDTO.MailFolder] = [:]
    ) -> GraphMappedMessage? {
        guard let providerMessageId = dto.id else { return nil }

        let id = scopedExternalId(accountId: accountId, kind: "message", providerId: providerMessageId)
        let threadId = dto.conversationId.map {
            scopedExternalId(accountId: accountId, kind: "conversation", providerId: $0)
        } ?? id
        let mailbox = dto.parentFolderId.flatMap { folderId in
            canonicalMailbox(forFolderId: folderId, foldersById: foldersById, accountId: accountId)
        }
        let (bodyText, bodyHTML) = bodies(from: dto.body)
        let categories = dto.categories ?? []
        let isFlagged = isFlagged(dto.flag)
        let isInTrash = mailbox == .trash
        let message = MailDomain.Message(
            id: id,
            threadId: threadId,
            accountId: accountId,
            messageIdHeader: dto.internetMessageId,
            from: address(from: dto.from ?? dto.sender),
            to: addresses(from: dto.toRecipients),
            cc: addresses(from: dto.ccRecipients),
            sentAt: date(from: dto.sentDateTime) ?? date(from: dto.receivedDateTime) ?? .distantPast,
            snippet: dto.bodyPreview,
            bodyText: bodyText,
            bodyHTML: bodyHTML,
            attachments: attachments(from: dto.attachments, messageId: id, accountId: accountId),
            isUnread: dto.isRead.map { !$0 } ?? false,
            isSentByMe: mailbox == .sent
        )
        var categoryMailboxes = categories.map(GraphMailboxMapper.canonicalCategory)
        if let flaggedMailbox = GraphMailboxMapper.canonicalFlaggedMailbox(isFlagged: isFlagged) {
            categoryMailboxes.append(flaggedMailbox)
        }

        return GraphMappedMessage(
            message: message,
            providerMessageId: providerMessageId,
            providerConversationId: dto.conversationId,
            providerParentFolderId: dto.parentFolderId,
            mailbox: mailbox,
            categories: categories,
            categoryMailboxes: categoryMailboxes,
            isFlagged: isFlagged,
            isInTrash: isInTrash
        )
    }

    private static func mapRemovedMessage(
        providerMessageId: String,
        accountId: String,
        providerParentFolderId: String?,
        reason: String?
    ) -> GraphRemovedMessage {
        let normalizedReason = reason?.lowercased()
        return GraphRemovedMessage(
            id: scopedExternalId(accountId: accountId, kind: "message", providerId: providerMessageId),
            accountId: accountId,
            providerMessageId: providerMessageId,
            providerParentFolderId: providerParentFolderId,
            reason: reason,
            isDeleted: normalizedReason == "deleted",
            isMoved: normalizedReason == "changed"
        )
    }

    private static func canonicalMailbox(
        forFolderId folderId: String,
        foldersById: [String: GraphDTO.MailFolder],
        accountId: String
    ) -> CanonicalMailbox {
        guard let folder = foldersById[folderId] else {
            return .userDefined(
                id: scopedExternalId(accountId: accountId, kind: "folder", providerId: folderId),
                name: nil,
                kind: .label
            )
        }
        return canonicalMailbox(
            forFolderName: folder.displayName,
            folderId: scopedExternalId(accountId: accountId, kind: "folder", providerId: folder.id)
        )
    }

    private static func canonicalMailbox(forFolderName displayName: String, folderId: String) -> CanonicalMailbox {
        let normalizedName = normalizedWellKnownFolderName(displayName)
        switch normalizedName {
        case "inbox", "sentitems", "drafts", "deleteditems", "junkemail", "archive":
            return GraphMailboxMapper.canonicalMailbox(
                forWellKnownFolder: normalizedName,
                folderID: folderId
            )
        default:
            return .userDefined(id: folderId, name: displayName, kind: .label)
        }
    }

    private static func normalizedWellKnownFolderName(_ displayName: String) -> String {
        displayName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func bodies(from body: GraphDTO.ItemBody?) -> (text: String?, html: String?) {
        guard let body, let content = body.content else { return (nil, nil) }
        switch body.contentType {
        case .html:
            return (nil, content)
        case .text:
            return (content, nil)
        case nil:
            return (content, nil)
        }
    }

    private static func address(from recipient: GraphDTO.Recipient?) -> Address? {
        guard let recipient else { return nil }
        let emailAddress = recipient.emailAddress
        guard let email = emailAddress.address?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            return nil
        }
        let name = emailAddress.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Address(name: name?.isEmpty == true ? nil : name, email: email)
    }

    private static func addresses(from recipients: [GraphDTO.Recipient]?) -> [Address] {
        recipients?.compactMap(address) ?? []
    }

    private static func attachments(
        from attachments: [GraphDTO.AttachmentMetadata]?,
        messageId: String,
        accountId: String
    ) -> [Attachment] {
        attachments?.compactMap { attachment in
            guard let providerAttachmentId = attachment.id else { return nil }
            return Attachment(
                id: scopedExternalId(accountId: accountId, kind: "attachment", providerId: providerAttachmentId),
                messageId: messageId,
                filename: attachment.name,
                mimeType: attachment.contentType,
                sizeBytes: attachment.size,
                contentId: normalizedContentId(attachment.contentId)
            )
        } ?? []
    }

    private static func normalizedContentId(_ contentId: String?) -> String? {
        let normalized = contentId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        return normalized?.isEmpty == true ? nil : normalized
    }

    private static func isFlagged(_ flag: GraphDTO.FollowupFlag?) -> Bool {
        flag?.flagStatus?.caseInsensitiveCompare("flagged") == .orderedSame
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
