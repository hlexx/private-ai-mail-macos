import Foundation
import MailDomain
import Testing
@testable import MailProviders

@Suite("GraphMapper")
struct GraphMapperTests {
    private let accountId = "outlook-account"

    @Test func mapsHtmlMessageMetadataAndScopedIds() throws {
        let folders = [
            "inbox-id": GraphDTO.MailFolder(id: "inbox-id", displayName: "Inbox")
        ]
        let dto = GraphDTO.Message(
            id: "graph-message-1",
            internetMessageId: "<graph-message-1@example.com>",
            conversationId: "conversation-1",
            parentFolderId: "inbox-id",
            subject: "Trust review",
            bodyPreview: "Ready for review",
            body: GraphDTO.ItemBody(contentType: .html, content: "<p>Ready</p>"),
            from: GraphDTO.Recipient(emailAddress: GraphDTO.EmailAddress(name: "Alice", address: "alice@example.com")),
            toRecipients: [
                GraphDTO.Recipient(emailAddress: GraphDTO.EmailAddress(name: "Bob", address: "bob@example.com"))
            ],
            ccRecipients: [
                GraphDTO.Recipient(emailAddress: GraphDTO.EmailAddress(address: "cc@example.com"))
            ],
            receivedDateTime: "2026-05-29T06:15:00Z",
            sentDateTime: "2026-05-29T06:14:59.500Z",
            isRead: false
        )

        let mapped = try #require(GraphMapper.mapMessage(dto, accountId: accountId, foldersById: folders))

        #expect(mapped.message.id == "outlook:outlook-account:message:graph-message-1")
        #expect(mapped.message.threadId == "outlook:outlook-account:conversation:conversation-1")
        #expect(mapped.message.accountId == accountId)
        #expect(mapped.providerMessageId == "graph-message-1")
        #expect(mapped.message.messageIdHeader == "<graph-message-1@example.com>")
        #expect(mapped.message.from?.name == "Alice")
        #expect(mapped.message.from?.email == "alice@example.com")
        #expect(mapped.message.to == [Address(name: "Bob", email: "bob@example.com")])
        #expect(mapped.message.cc == [Address(email: "cc@example.com")])
        #expect(mapped.message.bodyHTML == "<p>Ready</p>")
        #expect(mapped.message.bodyText == nil)
        #expect(mapped.message.snippet == "Ready for review")
        #expect(mapped.message.isUnread)
        #expect(mapped.message.sentAt == Date(timeIntervalSince1970: 1_780_035_299.5))
        #expect(mapped.mailbox == .inbox)
    }

    @Test func mapsTextBodyAttachmentsAndReadState() throws {
        let dto = GraphDTO.Message(
            id: "message-with-attachments",
            conversationId: "conversation-with-attachments",
            parentFolderId: "projects-id",
            body: GraphDTO.ItemBody(contentType: .text, content: "Plain body"),
            isRead: true,
            attachments: [
                GraphDTO.AttachmentMetadata(
                    id: "attachment-1",
                    name: "brief.pdf",
                    contentType: "application/pdf",
                    size: 2048,
                    isInline: false,
                    contentId: "<file-1>"
                ),
                GraphDTO.AttachmentMetadata(
                    id: nil,
                    name: "missing-id.pdf",
                    contentType: "application/pdf",
                    size: 1024
                ),
            ]
        )

        let mapped = try #require(GraphMapper.mapMessage(dto, accountId: accountId))

        #expect(mapped.message.bodyText == "Plain body")
        #expect(mapped.message.bodyHTML == nil)
        #expect(!mapped.message.isUnread)
        #expect(mapped.mailbox == .userDefined(
            id: "outlook:outlook-account:folder:projects-id",
            name: nil,
            kind: .label
        ))
        #expect(mapped.message.attachments.count == 1)
        #expect(mapped.message.attachments[0].id == "outlook:outlook-account:attachment:attachment-1")
        #expect(mapped.message.attachments[0].messageId == "outlook:outlook-account:message:message-with-attachments")
        #expect(mapped.message.attachments[0].accountId == accountId)
        #expect(mapped.message.attachments[0].filename == "brief.pdf")
        #expect(mapped.message.attachments[0].mimeType == "application/pdf")
        #expect(mapped.message.attachments[0].sizeBytes == 2048)
        #expect(mapped.message.attachments[0].contentId == "file-1")
        #expect(mapped.message.attachments[0].disposition == .attachment)
        #expect(mapped.message.attachments[0].byteFetchHandle == AttachmentByteFetchHandle(
            provider: .outlook,
            accountId: accountId,
            messageId: "message-with-attachments",
            attachmentId: "attachment-1"
        ))
    }

    @Test func mapsSentFolderFlaggedStateAndCategories() throws {
        let folders = [
            "sent-id": GraphDTO.MailFolder(id: "sent-id", displayName: "Sent Items")
        ]
        let dto = GraphDTO.Message(
            id: "sent-message",
            conversationId: "sent-conversation",
            parentFolderId: "sent-id",
            body: GraphDTO.ItemBody(contentType: .text, content: "Sent body"),
            isRead: true,
            categories: ["Client A", "Needs Reply"],
            flag: GraphDTO.FollowupFlag(flagStatus: "flagged")
        )

        let mapped = try #require(GraphMapper.mapMessage(dto, accountId: accountId, foldersById: folders))

        #expect(mapped.mailbox == .sent)
        #expect(mapped.message.isSentByMe)
        #expect(mapped.isFlagged)
        #expect(mapped.categories == ["Client A", "Needs Reply"])
        #expect(mapped.categoryMailboxes.contains(.userDefined(id: "Client A", name: "Client A", kind: .category)))
        #expect(mapped.categoryMailboxes.contains(.userDefined(id: "Needs Reply", name: "Needs Reply", kind: .category)))
        #expect(mapped.categoryMailboxes.contains(.flagged))
        #expect(!mapped.categoryMailboxes.contains(.starred))
    }

    @Test func mapsTrashFolderAsInTrashWithoutHardDelete() throws {
        let folders = [
            "deleted-id": GraphDTO.MailFolder(id: "deleted-id", displayName: "Deleted Items")
        ]
        let dto = GraphDTO.Message(
            id: "trashed-message",
            conversationId: "trashed-conversation",
            parentFolderId: "deleted-id",
            body: GraphDTO.ItemBody(contentType: .text, content: "Trash body"),
            isRead: true
        )

        let mapped = try #require(GraphMapper.mapMessage(dto, accountId: accountId, foldersById: folders))

        #expect(mapped.mailbox == .trash)
        #expect(mapped.isInTrash)
        #expect(mapped.message.id == "outlook:outlook-account:message:trashed-message")
    }

    @Test func mapsDeltaRemovedDeletedAndMovedChanges() throws {
        let deleted = GraphDTO.Message(
            id: "deleted-message",
            parentFolderId: "inbox-id",
            odataRemoved: GraphDTO.Removed(reason: "deleted")
        )
        let moved = GraphDTO.Message(
            id: "moved-message",
            parentFolderId: "inbox-id",
            odataRemoved: GraphDTO.Removed(reason: "changed")
        )

        let deletedChange = try #require(GraphMapper.mapMessageChange(deleted, accountId: accountId))
        let movedChange = try #require(GraphMapper.mapMessageChange(moved, accountId: accountId))

        guard case .removed(let deletedRemoval) = deletedChange else {
            Issue.record("Expected deleted removal")
            return
        }
        guard case .removed(let movedRemoval) = movedChange else {
            Issue.record("Expected moved removal")
            return
        }

        #expect(deletedRemoval.id == "outlook:outlook-account:message:deleted-message")
        #expect(deletedRemoval.providerMessageId == "deleted-message")
        #expect(deletedRemoval.reason == "deleted")
        #expect(deletedRemoval.isDeleted)
        #expect(!deletedRemoval.isMoved)
        #expect(movedRemoval.id == "outlook:outlook-account:message:moved-message")
        #expect(movedRemoval.reason == "changed")
        #expect(!movedRemoval.isDeleted)
        #expect(movedRemoval.isMoved)
    }

    @Test func mapsFoldersToCanonicalMailboxesWithScopedCustomIds() {
        let inbox = GraphMapper.mapFolder(
            GraphDTO.MailFolder(id: "inbox-id", displayName: "Inbox", unreadItemCount: 3, totalItemCount: 10),
            accountId: accountId
        )
        let custom = GraphMapper.mapFolder(
            GraphDTO.MailFolder(id: "project-id", displayName: "Project A", parentFolderId: "root"),
            accountId: accountId
        )

        #expect(inbox.id == "outlook:outlook-account:folder:inbox-id")
        #expect(inbox.mailbox == .inbox)
        #expect(inbox.unreadCount == 3)
        #expect(inbox.totalCount == 10)
        #expect(custom.mailbox == .userDefined(
            id: "outlook:outlook-account:folder:project-id",
            name: "Project A",
            kind: .label
        ))
        #expect(custom.parentProviderFolderId == "root")
    }
}
