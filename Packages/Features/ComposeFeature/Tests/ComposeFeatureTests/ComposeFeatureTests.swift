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

// MARK: - ComposeWindowView Snapshot Tests

@Suite("ComposeWindowView Snapshots")
struct ComposeWindowViewSnapshotTests {

    @MainActor
    @Test func composeWindowDark() {
        let view = ComposeWindowView()
            .preferredColorScheme(.dark)
            .frame(width: 720, height: 560)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 560)
        host.layout()
    }

    @MainActor
    @Test func composeWindowLight() {
        let view = ComposeWindowView()
            .preferredColorScheme(.light)
            .frame(width: 720, height: 560)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 560)
        host.layout()
    }

    @MainActor
    @Test func composeWindowCompactSize() {
        let view = ComposeWindowView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 480)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 480)
        host.layout()
    }

    @MainActor
    @Test func composeWindowWideSize() {
        let view = ComposeWindowView()
            .preferredColorScheme(.light)
            .frame(width: 900, height: 700)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        host.layout()
    }
}

// MARK: - RichTextEditor Tests

@Suite("RichTextEditor")
struct RichTextEditorTests {

    @MainActor
    @Test func richTextEditorRendersWithContent() {
        let text = NSAttributedString(string: "Hello, world!")
        let binding = Binding.constant(text)
        let view = RichTextEditor(attributedText: binding)
            .frame(width: 400, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        host.layout()
    }
}
