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
}
