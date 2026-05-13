import Testing
import SwiftUI
import AppKit
@testable import ComposeFeature

@Suite("ComposeFeature")
struct ComposeFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ComposeFeature.moduleName == "ComposeFeature")
    }

    @Test func composeToneHasThreeCases() {
        #expect(ComposeTone.allCases.count == 3)
        #expect(ComposeTone.allCases.map(\.rawValue) == ["concise", "warm", "direct"])
    }
}

// MARK: - InlineComposer Snapshot Tests

@Suite("InlineComposer Snapshots")
struct InlineComposerSnapshotTests {

    @MainActor
    @Test func inlineComposerDark() {
        let view = InlineComposer()
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 400)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layout()
    }

    @MainActor
    @Test func inlineComposerLight() {
        let view = InlineComposer()
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .preferredColorScheme(.light)
            .frame(width: 600, height: 400)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layout()
    }

    @MainActor
    @Test func inlineComposerWithCustomEvidence() {
        let view = InlineComposer(evidence: ["msg_2"])
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 400)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layout()
    }
}
