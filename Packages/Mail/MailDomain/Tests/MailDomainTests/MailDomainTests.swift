import Foundation
import Testing
@testable import MailDomain

@Suite("MailDomain")
struct MailDomainTests {
    @Test func addressParsingRFC822() {
        let addr = Address(rfc822: "Alice Smith <alice@example.com>")
        #expect(addr?.name == "Alice Smith")
        #expect(addr?.email == "alice@example.com")
    }

    @Test func addressParsingPlain() {
        let addr = Address(rfc822: "bob@example.com")
        #expect(addr?.name == nil)
        #expect(addr?.email == "bob@example.com")
    }

    @Test func providerIdentifierPreservesRawCompatibility() {
        #expect(MailProviderIdentifier.gmail.rawValue == "gmail")
        #expect(MailProviderIdentifier.outlook.rawValue == "outlook")
        #expect(MailProviderIdentifier.microsoftGraph == .outlook)

        let existing = MailProviderIdentifier(rawValue: "gmail")
        #expect(existing == .gmail)
        #expect(existing.isTrustMVPSupported)

        let unknown = MailProviderIdentifier(rawValue: "custom-provider")
        #expect(!unknown.isTrustMVPSupported)
        #expect(unknown.rawValue == "custom-provider")
    }

    @Test func gmailCanonicalMailboxRoundTrips() {
        let pairs: [(String, CanonicalMailbox)] = [
            ("INBOX", .inbox),
            ("SENT", .sent),
            ("DRAFT", .drafts),
            ("TRASH", .trash),
            ("SPAM", .spam),
            ("STARRED", .starred),
        ]

        for (labelID, canonical) in pairs {
            #expect(GmailMailboxMapper.canonicalMailbox(forLabelID: labelID) == canonical)
            #expect(GmailMailboxMapper.gmailLabelID(for: canonical) == labelID)
        }

        let custom = GmailMailboxMapper.canonicalMailbox(forLabelID: "Label_123", name: "Projects")
        #expect(custom == .userDefined(id: "Label_123", name: "Projects", kind: .label))
        #expect(GmailMailboxMapper.gmailLabelID(for: custom) == "Label_123")
        #expect(GmailMailboxMapper.isArchived(labelIDs: ["CATEGORY_UPDATES"]))
        #expect(!GmailMailboxMapper.isArchived(labelIDs: ["INBOX", "CATEGORY_UPDATES"]))
    }

    @Test func graphCanonicalMailboxRoundTrips() {
        let pairs: [(String, CanonicalMailbox)] = [
            ("inbox", .inbox),
            ("sentitems", .sent),
            ("drafts", .drafts),
            ("deleteditems", .trash),
            ("junkemail", .spam),
            ("archive", .archive),
        ]

        for (folderName, canonical) in pairs {
            #expect(GraphMailboxMapper.canonicalMailbox(forWellKnownFolder: folderName) == canonical)
            #expect(GraphMailboxMapper.graphWellKnownFolder(for: canonical) == folderName)
        }

        let projectFolder = GraphMailboxMapper.canonicalMailbox(forWellKnownFolder: "Project A", folderID: "A")
        #expect(projectFolder == .userDefined(id: "A", name: "Project A", kind: .label))

        let category = GraphMailboxMapper.canonicalCategory(name: "ImportantClient")
        #expect(category == .userDefined(id: "ImportantClient", name: "ImportantClient", kind: .category))

        #expect(GraphMailboxMapper.canonicalFlaggedMailbox(isFlagged: true) == .flagged)
        #expect(GraphMailboxMapper.canonicalFlaggedMailbox(isFlagged: false) == nil)
    }

    @Test func sendQueueDomainContractsCaptureIdentityRetryAndSanitizedFailure() throws {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let retryAt = Date(timeIntervalSince1970: 1_060)
        let failure = SanitizedSendFailure(
            category: .rateLimited,
            providerErrorCode: "429",
            userVisibleMessage: "Provider asked us to retry later.",
            retryAfterSeconds: 60,
            occurredAt: createdAt
        )

        let queued = QueuedOutgoingMessage(
            id: "queue-1",
            draftID: "draft-1",
            provider: .gmail,
            accountID: "account-1",
            idempotencyKey: "idem-1",
            status: .retryScheduled,
            from: Address(name: "User", email: "user@example.com"),
            to: [Address(email: "recipient@example.com")],
            subject: "Status",
            bodyText: "Local body",
            threadID: "thread-1",
            replyToProviderMessageID: "provider-original",
            rfcMessageID: "<local@hlexx.privateaimail>",
            rfcInReplyTo: "<parent@example.com>",
            rfcReferences: ["<parent@example.com>"],
            attempts: 1,
            nextAttemptAt: retryAt,
            createdAt: createdAt,
            updatedAt: retryAt,
            sanitizedFailure: failure
        )

        #expect(queued.bodyStorage == .sqlite)
        #expect(queued.retryPolicy.delaySeconds(forNextAttemptAfter: 1) == 60)
        #expect(queued.retryPolicy.delaySeconds(forNextAttemptAfter: 5) == nil)
        #expect(queued.sanitizedFailure?.category == .rateLimited)
        #expect(queued.sanitizedFailure?.providerErrorCode == "429")

        let encoded = try JSONEncoder().encode(queued)
        let decoded = try JSONDecoder().decode(QueuedOutgoingMessage.self, from: encoded)
        #expect(decoded == queued)
    }

    @Test func draftIdentityAndProviderSendResultStayProviderNeutral() {
        let identity = DraftIdentity(provider: .outlook, accountID: "account-2", id: "draft-2")
        let sentAt = Date(timeIntervalSince1970: 2_000)
        let result = ProviderSendResult(
            provider: .outlook,
            providerMessageID: "graph-message",
            providerThreadID: "graph-thread",
            rfcMessageID: "<sent@example.com>",
            sentAt: sentAt
        )

        #expect(identity.provider == .outlook)
        #expect(identity.id.rawValue == "draft-2")
        #expect(result.provider == .outlook)
        #expect(result.providerMessageID == "graph-message")
        #expect(result.rfcMessageID == "<sent@example.com>")
    }
}
