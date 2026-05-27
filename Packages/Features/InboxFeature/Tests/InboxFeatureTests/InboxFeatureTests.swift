import Testing
import SwiftUI
import AppKit
@testable import InboxFeature
import DesignSystem

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
        #expect(cases[1] == .needsReply)
        #expect(cases[2] == .hasDeadline)
        #expect(cases[3] == .hasAttachment)
        #expect(cases[4] == .aiHandled)
    }

    @Test func filterLabelsAreNonEmpty() {
        for f in ThreadFilter.allCases {
            #expect(!f.label.isEmpty, "Filter \(f) should have a non-empty label")
        }
    }
}

// MARK: - InboxView Snapshot Tests

@Suite("InboxView Snapshots")
struct InboxViewSnapshotTests {

    @MainActor
    @Test func filterChipsRowDark() {
        let view = filterChipsView()
            .preferredColorScheme(.dark)
            .frame(width: 360, height: 50)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 50)
        host.layout()
    }

    @MainActor
    @Test func filterChipsRowLight() {
        let view = filterChipsView()
            .preferredColorScheme(.light)
            .frame(width: 360, height: 50)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 50)
        host.layout()
    }

    @MainActor
    @Test func threadListHeaderDark() {
        let view = headerView()
            .preferredColorScheme(.dark)
            .frame(width: 360, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 60)
        host.layout()
    }

    @MainActor
    @Test func threadListHeaderLight() {
        let view = headerView()
            .preferredColorScheme(.light)
            .frame(width: 360, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 60)
        host.layout()
    }

    @MainActor
    @Test func emptyStateDark() {
        let view = ContentUnavailableView(
            String(localized: "threads.empty.title", defaultValue: "No threads yet"),
            systemImage: "envelope.open",
            description: Text("Connect a Gmail account to get started.")
        )
        .preferredColorScheme(.dark)
        .frame(width: 360, height: 300)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 300)
        host.layout()
    }

    @MainActor
    @Test func emptyStateLight() {
        let view = ContentUnavailableView(
            String(localized: "threads.empty.title", defaultValue: "No threads yet"),
            systemImage: "envelope.open",
            description: Text("Connect a Gmail account to get started.")
        )
        .preferredColorScheme(.light)
        .frame(width: 360, height: 300)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 300)
        host.layout()
    }

    @MainActor
    private func filterChipsView() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                RBFilterChip(label: "All", isOn: true) {}
                RBFilterChip(label: "Needs reply", isOn: false) {}
                RBFilterChip(label: "Has deadline", isOn: false) {}
                RBFilterChip(label: "Attachments", isOn: false) {}
                RBFilterChip(label: "AI handled", isOn: false) {}
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.rbBgCanvas)
    }

    @MainActor
    private func headerView() -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Inbox")
                .font(.rbGeist(18, weight: .semibold))
                .foregroundStyle(Color.rbFg1)
            Spacer()
            Text("12 threads · 3 need reply")
                .font(.rbMono(11))
                .foregroundStyle(Color.rbFg3)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Color.rbBgCanvas)
    }
}
