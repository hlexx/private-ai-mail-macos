import Foundation
import MailDomain
@testable import MailProviders
import Testing

@Suite("Provider Fixture Contracts", .serialized)
struct ProviderFixtureContractTests {
    private let gmailAccountId = "gmail-fixture-account"
    private let outlookAccountId = "outlook-fixture-account"

    @Test func fixtureCorpusIsSyntheticAndCredentialFree() throws {
        let files = try ProviderFixtureLoader.allFixtureFiles()
        #expect(files.count >= 10)

        let forbiddenMarkers = [
            "access_token",
            "refresh_token",
            "authorization:",
            "bearer ",
            "ya29.",
            "sk-",
            "xoxb-",
            "private mail",
            "real customer",
            "@gmail.com",
            "@outlook.com",
            "@hotmail.com",
            "@icloud.com",
        ]

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8).lowercased()
            for marker in forbiddenMarkers {
                #expect(!content.contains(marker), "\(file.lastPathComponent) contains \(marker)")
            }
        }
    }

    @Test func gmailFixturesCoverLabelsHistoryMessagesAndAttachments() throws {
        let labelList = try ProviderFixtureLoader.decode(GmailDTO.LabelList.self, "gmail/labels.json")
        let labels = try #require(labelList.labels)
        let labelIds = Set(labels.map(\.id))
        #expect(labelIds.isSuperset(of: ["INBOX", "SENT", "STARRED", "Label_ProjectAlpha"]))

        let projectLabel = try #require(labels.first { $0.id == "Label_ProjectAlpha" })
        #expect(GmailMailboxMapper.canonicalMailbox(
            forLabelID: projectLabel.id,
            name: projectLabel.name
        ) == .userDefined(id: "Label_ProjectAlpha", name: "Project Alpha", kind: .label))

        let history = try ProviderFixtureLoader.decode(GmailDTO.HistoryResponse.self, "gmail/history.json")
        let historyRecords = try #require(history.history)
        #expect(history.historyId == "history-102")
        #expect(historyRecords.count == 2)
        #expect(historyRecords[0].messagesAdded?.first?.message.id == "gmail-overlap-inbox-1")
        #expect(historyRecords[0].labelsAdded?.first?.labelIds == ["STARRED"])
        #expect(historyRecords[0].labelsRemoved?.first?.labelIds == ["UNREAD"])
        #expect(historyRecords[1].messagesDeleted?.first?.message.id == "gmail-removed-1")

        let dto = try ProviderFixtureLoader.decode(GmailDTO.Message.self, "gmail/message_with_attachment.json")
        let mapped = GmailMapper.mapMessageWithLabels(dto, accountId: gmailAccountId)

        #expect(mapped.labelIds == ["INBOX", "UNREAD", "STARRED", "Label_ProjectAlpha"])
        #expect(mapped.message.bodyText == "Hello provider.")
        #expect(mapped.message.bodyHTML == "<p>Hello provider.</p>")
        #expect(mapped.message.isUnread)
        #expect(mapped.message.attachments.count == 2)

        let externalAttachment = try #require(mapped.message.attachments.first { $0.byteFetchHandle != nil })
        #expect(externalAttachment.id == "gmail-att-brief-pdf")
        #expect(externalAttachment.filename == "trust-brief.pdf")
        #expect(externalAttachment.mimeType == "application/pdf")
        #expect(externalAttachment.sizeBytes == 2048)
        #expect(externalAttachment.contentId == "brief-pdf@example")
        #expect(externalAttachment.disposition == .attachment)
        #expect(externalAttachment.byteFetchHandle == AttachmentByteFetchHandle(
            provider: .gmail,
            accountId: gmailAccountId,
            messageId: "gmail-overlap-inbox-1",
            attachmentId: "gmail-att-brief-pdf"
        ))

        let inlineAttachment = try #require(mapped.message.attachments.first { $0.inlineData != nil })
        #expect(inlineAttachment.id == "inline_logo@example")
        #expect(inlineAttachment.contentId == "logo@example")
        #expect(inlineAttachment.disposition == .inline)

        let attachmentBody = try ProviderFixtureLoader.decode(
            GmailDTO.MessagePartBody.self,
            "gmail/attachment_brief.json"
        )
        let attachmentData = try ProviderFixtureLoader.base64URLDecode(try #require(attachmentBody.data))
        #expect(String(data: attachmentData, encoding: .utf8) == "Hello provider.")
    }

    @Test func graphFixturesCoverFoldersDeltaMessagesAndAttachments() throws {
        let folderList = try ProviderFixtureLoader.decode(GraphDTO.MailFolderList.self, "graph/folders.json")
        let foldersById = Dictionary(uniqueKeysWithValues: folderList.value.map { ($0.id, $0) })
        let inboxFolder = try #require(foldersById["inbox-id"])
        let projectFolder = try #require(foldersById["projects-id"])

        let mappedInbox = GraphMapper.mapFolder(inboxFolder, accountId: outlookAccountId)
        let mappedProject = GraphMapper.mapFolder(projectFolder, accountId: outlookAccountId)
        #expect(mappedInbox.mailbox == .inbox)
        #expect(mappedInbox.unreadCount == 2)
        #expect(mappedProject.mailbox == .userDefined(
            id: "outlook:outlook-fixture-account:folder:projects-id",
            name: "Project Alpha",
            kind: .label
        ))

        let delta = try ProviderFixtureLoader.decode(GraphDTO.MessageDeltaResponse.self, "graph/delta_messages.json")
        #expect(delta.value.count == 2)
        #expect(delta.nextLink?.contains("fixture-delta-next") == true)
        #expect(delta.deltaLink?.contains("fixture-delta-cursor") == true)

        let messageDTO = try #require(delta.value.first { $0.id == "graph-overlap-inbox-1" })
        let mappedMessage = try #require(GraphMapper.mapMessage(
            messageDTO,
            accountId: outlookAccountId,
            foldersById: foldersById
        ))
        #expect(mappedMessage.mailbox == .inbox)
        #expect(mappedMessage.message.bodyText == "Hello provider.")
        #expect(mappedMessage.message.bodyHTML == nil)
        #expect(mappedMessage.message.isUnread)
        #expect(mappedMessage.isFlagged)
        #expect(mappedMessage.categoryMailboxes.contains(.flagged))
        #expect(mappedMessage.categoryMailboxes.contains(.userDefined(
            id: "Project Alpha",
            name: "Project Alpha",
            kind: .category
        )))

        let externalAttachment = try #require(mappedMessage.message.attachments.first)
        #expect(externalAttachment.id == "outlook:outlook-fixture-account:attachment:graph-att-brief-pdf")
        #expect(externalAttachment.messageId == "outlook:outlook-fixture-account:message:graph-overlap-inbox-1")
        #expect(externalAttachment.filename == "trust-brief.pdf")
        #expect(externalAttachment.mimeType == "application/pdf")
        #expect(externalAttachment.sizeBytes == 2048)
        #expect(externalAttachment.contentId == "brief-pdf@example")
        #expect(externalAttachment.disposition == .attachment)
        #expect(externalAttachment.byteFetchHandle == AttachmentByteFetchHandle(
            provider: .outlook,
            accountId: outlookAccountId,
            messageId: "graph-overlap-inbox-1",
            attachmentId: "graph-att-brief-pdf"
        ))

        let removedDTO = try #require(delta.value.first { $0.id == "graph-removed-1" })
        let removedChange = try #require(GraphMapper.mapMessageChange(removedDTO, accountId: outlookAccountId))
        guard case .removed(let removal) = removedChange else {
            Issue.record("Expected Graph removed delta fixture")
            return
        }
        #expect(removal.id == "outlook:outlook-fixture-account:message:graph-removed-1")
        #expect(removal.isDeleted)
        #expect(!removal.isMoved)

        let attachments = try ProviderFixtureLoader.decode(GraphDTO.AttachmentList.self, "graph/attachments.json")
        #expect(attachments.value.count == 2)
        #expect(attachments.value.first?.name == "trust-brief.pdf")
        #expect(attachments.value.last?.isInline == true)

        let attachmentContent = try ProviderFixtureLoader.decode(
            GraphDTO.AttachmentContent.self,
            "graph/attachment_brief.json"
        )
        let attachmentBytes = try #require(attachmentContent.contentBytes)
        let attachmentData = try #require(Data(base64Encoded: attachmentBytes))
        #expect(String(data: attachmentData, encoding: .utf8) == "Hello provider.")
    }

    @Test func overlappingProviderFixturesMapToSharedSearchProjection() throws {
        let gmailDTO = try ProviderFixtureLoader.decode(GmailDTO.Message.self, "gmail/message_with_attachment.json")
        let gmailMapped = GmailMapper.mapMessageWithLabels(gmailDTO, accountId: gmailAccountId)
        let gmailMailboxes = Set(gmailMapped.labelIds.map {
            GmailMailboxMapper.canonicalMailbox(forLabelID: $0)
        })

        let graphFolders = try ProviderFixtureLoader.decode(GraphDTO.MailFolderList.self, "graph/folders.json")
        let graphFoldersById = Dictionary(uniqueKeysWithValues: graphFolders.value.map { ($0.id, $0) })
        let graphDelta = try ProviderFixtureLoader.decode(GraphDTO.MessageDeltaResponse.self, "graph/delta_messages.json")
        let graphDTO = try #require(graphDelta.value.first { $0.id == "graph-overlap-inbox-1" })
        let graphMapped = try #require(GraphMapper.mapMessage(
            graphDTO,
            accountId: outlookAccountId,
            foldersById: graphFoldersById
        ))

        #expect(gmailMailboxes.contains(.inbox))
        #expect(graphMapped.mailbox == .inbox)
        #expect(!GmailMailboxMapper.isArchived(labelIDs: gmailMapped.labelIds))
        #expect(ProviderSearchProjection(message: gmailMapped.message) == ProviderSearchProjection(message: graphMapped.message))
    }

    @Test func sendExecutorsReturnProviderNeutralResultsForSameRequest() async throws {
        let sentAt = Date(timeIntervalSince1970: 1_780_035_299.5)
        let gmailSent = try ProviderFixtureLoader.decode(GmailDTO.SentMessage.self, "gmail/send_success.json")
        let gmailAPI = FixtureGmailSendAPI(sentMessage: gmailSent)
        let graphAPI = FixtureGraphSendAPI(
            result: GraphDTO.SendResult(accepted: true, statusCode: 202, requestId: "graph-request-fixture")
        )

        let gmailRequest = sendRequest(provider: .gmail)
        let graphRequest = sendRequest(provider: .outlook)
        let gmailResult = try await GmailSendExecutor(api: gmailAPI, now: { sentAt }).send(gmailRequest)
        let graphResult = try await GraphSendExecutor(api: graphAPI, now: { sentAt }).send(graphRequest)

        #expect(gmailResult.provider == .gmail)
        #expect(gmailResult.providerMessageID == gmailSent.id)
        #expect(gmailResult.providerThreadID == gmailSent.threadId)
        #expect(gmailResult.rfcMessageID == "<fixture-send-1@mail.example.com>")
        #expect(gmailResult.sentAt == sentAt)
        #expect(gmailAPI.lastThreadID == "gmail-thread-overlap-1")

        let gmailRaw = try #require(gmailAPI.lastRaw)
        let rawData = try #require(MIMEBuilder.base64URLDecode(gmailRaw))
        let rawMessage = try #require(String(data: rawData, encoding: .utf8))
        #expect(rawMessage.contains("Subject: Trust review"))
        #expect(rawMessage.contains("To: User Example <user@example.com>"))
        #expect(rawMessage.contains("Hello provider."))

        let capturedGraphRequest = try #require(graphAPI.lastRequest)
        #expect(graphResult.provider == .outlook)
        #expect(graphResult.providerRequestID == "graph-request-fixture")
        #expect(graphResult.sentAt == sentAt)
        #expect(capturedGraphRequest.message.subject == gmailRequest.subject)
        #expect(capturedGraphRequest.message.body?.contentType == .text)
        #expect(capturedGraphRequest.message.body?.content == gmailRequest.bodyText)
        #expect(capturedGraphRequest.message.toRecipients?.first?.emailAddress.address == "user@example.com")
    }

    private func sendRequest(provider: MailProviderIdentifier) -> ProviderSendRequest {
        ProviderSendRequest(
            provider: provider,
            accountID: provider == .gmail ? gmailAccountId : outlookAccountId,
            idempotencyKey: "fixture-send-1",
            from: Address(name: "Ava Example", email: "ava@example.com"),
            to: [Address(name: "User Example", email: "user@example.com")],
            subject: "Trust review",
            bodyText: "Hello provider.",
            threadID: provider == .gmail ? "gmail-thread-overlap-1" : nil,
            rfcMessageID: "<fixture-send-1@mail.example.com>"
        )
    }
}

private struct ProviderSearchProjection: Equatable {
    let senderEmail: String?
    let recipientEmails: [String]
    let snippet: String?
    let bodyText: String?
    let isUnread: Bool
    let externalAttachmentNames: [String]
    let externalAttachmentTypes: [String]

    init(message: MailDomain.Message) {
        let externalAttachments = message.attachments.filter { $0.byteFetchHandle != nil }
        senderEmail = message.from?.email
        recipientEmails = message.to.map(\.email).sorted()
        snippet = message.snippet
        bodyText = message.bodyText
        isUnread = message.isUnread
        externalAttachmentNames = externalAttachments.compactMap(\.filename).sorted()
        externalAttachmentTypes = externalAttachments.compactMap(\.mimeType).sorted()
    }
}
