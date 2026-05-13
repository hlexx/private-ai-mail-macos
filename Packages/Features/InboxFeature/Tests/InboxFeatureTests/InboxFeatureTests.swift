import Testing
import SwiftUI
import AppKit
@testable import InboxFeature

@Suite("InboxFeature")
struct InboxFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(InboxFeature.moduleName == "InboxFeature")
    }

    // MARK: - ThreadRow

    @Test func threadRowExtractsNameFromDisplayFormat() {
        let name = ThreadRow.extractName(from: "Marta Kowalski <marta@example.com>")
        #expect(name == "Marta Kowalski")
    }

    @Test func threadRowExtractsNameFromBareEmail() {
        let name = ThreadRow.extractName(from: "alex@studio.eu")
        #expect(name == "alex")
    }

    @Test func threadRowExtractsNameFromEmptyString() {
        let name = ThreadRow.extractName(from: "")
        #expect(name == "?")
    }

    @Test func threadRowExtractsNameWithQuotes() {
        let name = ThreadRow.extractName(from: "\"Jonas R.\" <jonas@example.com>")
        #expect(name == "Jonas R.")
    }

    // MARK: - ThreadFilter

    @Test func filterAllCasesMatchDesign() {
        let cases = ThreadFilter.allCases
        #expect(cases.count == 5)
        #expect(cases[0] == .all)
        #expect(cases[0].label == "All")
        #expect(cases[1] == .needsReply)
        #expect(cases[1].label == "Needs reply")
        #expect(cases[2] == .hasDeadline)
        #expect(cases[2].label == "Has deadline")
        #expect(cases[3] == .hasAttachment)
        #expect(cases[3].label == "Attachments")
        #expect(cases[4] == .aiHandled)
        #expect(cases[4].label == "AI handled")
    }
}
