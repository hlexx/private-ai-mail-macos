import Foundation
import Testing

@Suite("Trust MVP sequencing document")
struct TrustMVPSequencingDocumentTests {
    @Test func documentNamesEightTranchesAndDeferredTrustMVPCapabilities() throws {
        let document = try Self.loadSequencingDocument()

        for number in 1...8 {
            #expect(document.contains("### Tranche \(number):"))
        }

        #expect(document.contains("Microsoft Graph network calls: planned"))
        #expect(document.contains("Full local search: planned"))
        #expect(document.contains("Send queue: planned"))
        #expect(document.contains("Broad attachment preview: planned"))
        #expect(document.contains("Status: in progress for this plan until validation passes."))
        #expect(document.contains("Status: planned."))
    }

    @Test func documentKeepsEMAILALFFollowUpOutOfAppPlan() throws {
        let document = try Self.loadSequencingDocument()

        #expect(document.contains("Do not edit `../EMAIL_ALF` from this app implementation plan."))
        #expect(document.contains("`../EMAIL_ALF/04_product_requirements.md`"))
        #expect(document.contains("`../EMAIL_ALF/07_architecture.md`"))
        #expect(document.contains("`../EMAIL_ALF/08_security_privacy.md`"))
        #expect(document.contains("`../EMAIL_ALF/10_roadmap.md`"))
    }

    @Test func adrRecordsMicrosoftGraphDeltaScopesAndNonGoals() throws {
        let document = try Self.loadADR0005()

        #expect(document.contains("Message delta is scoped to one mail folder at a time."))
        #expect(document.contains("`@odata.nextLink`"))
        #expect(document.contains("`@odata.deltaLink`"))
        #expect(document.contains("opaque to the client"))
        #expect(document.contains("`Mail.ReadWrite`"))
        #expect(document.contains("`Mail.Send`"))
        #expect(document.contains("`offline_access`"))
        #expect(document.contains("`openid`, `profile`, and `email`"))
        #expect(document.contains("Application permissions and app-only daemon access are"))
        #expect(document.contains("shared mailboxes, delegated"))
        #expect(document.contains("https://learn.microsoft.com/en-us/graph/delta-query-messages"))
        #expect(document.contains("https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc"))
    }

    private static func loadSequencingDocument() throws -> String {
        try loadDocument("docs/trust-mvp-sequencing.md")
    }

    private static func loadADR0005() throws -> String {
        try loadDocument("docs/adr/0005-trust-mvp-gmail-outlook-provider-contracts.md")
    }

    private static func loadDocument(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.append(path: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
