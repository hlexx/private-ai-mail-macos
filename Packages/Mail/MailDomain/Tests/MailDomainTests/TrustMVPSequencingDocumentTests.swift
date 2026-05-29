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

    private static func loadSequencingDocument() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.append(path: "docs/trust-mvp-sequencing.md")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
