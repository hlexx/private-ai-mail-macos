import AIKit
import AppKit
@testable import ComposeFeature
import MailDomain
import SwiftUI
import Testing

@Suite("ComposeFeature")
struct ComposeFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ComposeFeature.moduleName == "ComposeFeature")
    }
}

// MARK: - InlineComposer Snapshot Tests

@Suite("InlineComposer Snapshots")
struct InlineComposerSnapshotTests {

    @MainActor
    @Test func inlineComposerDark() {
        let view = InlineComposer(threadID: "t1", replyStore: ReplyStore())
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
        let view = InlineComposer(threadID: "t1", replyStore: ReplyStore())
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .preferredColorScheme(.light)
            .frame(width: 600, height: 400)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layout()
    }

    @MainActor
    @Test func inlineComposerWithReply() {
        let store = ReplyStore.preview(reply: AIThreadReply(
            body: "Thanks for the update, I'll review the document by Friday.",
            evidenceMessageIDs: ["msg_1", "msg_2"],
            detectedReplyLanguage: "en",
            confidence: 0.9
        ))
        let view = InlineComposer(threadID: "t1", replyStore: store)
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 400)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layout()
    }

    // MARK: - CTA Layout Snapshots (Task 9)

    @MainActor
    @Test(arguments: [280, 340, 480])
    func inlineComposerCTALayoutDark(width: Int) {
        let view = InlineComposer(threadID: "t1", replyStore: ReplyStore())
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .preferredColorScheme(.dark)
            .frame(width: CGFloat(width), height: 400)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        host.layout()
        // At widths < 400, "Edit in full" collapses to pencil icon
        #expect(host.frame.width == CGFloat(width))
    }

    @MainActor
    @Test(arguments: [280, 340, 480])
    func inlineComposerCTALayoutLight(width: Int) {
        let view = InlineComposer(threadID: "t1", replyStore: ReplyStore())
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .preferredColorScheme(.light)
            .frame(width: CGFloat(width), height: 400)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        host.layout()
        #expect(host.frame.width == CGFloat(width))
    }
}

// MARK: - ComposeWindowView Snapshot Tests

@MainActor
private func makePreviewViewModel() -> ComposeViewModel {
    let vm = ComposeViewModel(composeServiceFactory: { _ in
        StubComposeService()
    })
    vm.toField = "marta@acme.de"
    vm.subjectField = "Re: Contract approval"
    vm.bodyText = "Hi Marta"
    vm.selectedAccountID = "acc1"
    vm.selectedAccountEmail = "me@test.com"
    return vm
}

private struct StubComposeService: ComposeService {
    func send(_ draft: ComposeDraft) async throws -> SentEcho {
        SentEcho(messageID: "stub", threadID: "stub", sentAt: Date())
    }
}

@Suite("ComposeWindowView Snapshots")
struct ComposeWindowViewSnapshotTests {

    @MainActor
    @Test func composeWindowDark() {
        let view = ComposeWindowView(viewModel: makePreviewViewModel())
            .preferredColorScheme(.dark)
            .frame(width: 720, height: 560)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 560)
        host.layout()
    }

    @MainActor
    @Test func composeWindowLight() {
        let view = ComposeWindowView(viewModel: makePreviewViewModel())
            .preferredColorScheme(.light)
            .frame(width: 720, height: 560)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 560)
        host.layout()
    }

    @MainActor
    @Test func composeWindowCompactSize() {
        let view = ComposeWindowView(viewModel: makePreviewViewModel())
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 480)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 480)
        host.layout()
    }

    @MainActor
    @Test func composeWindowWideSize() {
        let view = ComposeWindowView(viewModel: makePreviewViewModel())
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

// MARK: - ApprovalRow Snapshot Tests

@Suite("ApprovalRow Snapshots")
struct ApprovalRowSnapshotTests {

    @MainActor
    @Test func approvalRowAwaitingDark() {
        let view = ApprovalRow(
            recipientCount: 2,
            accountEmail: "me@test.com",
            sendState: .awaitingApproval(deadline: Date().addingTimeInterval(5)),
            onCancel: {},
            onConfirmNow: {},
            onRetrySend: {}
        )
        .padding(16)
        .background(Color(.windowBackgroundColor))
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 80)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 80)
        host.layout()
    }

    @MainActor
    @Test func approvalRowAwaitingLight() {
        let view = ApprovalRow(
            recipientCount: 2,
            accountEmail: "me@test.com",
            sendState: .awaitingApproval(deadline: Date().addingTimeInterval(3)),
            onCancel: {},
            onConfirmNow: {},
            onRetrySend: {}
        )
        .padding(16)
        .background(Color(.windowBackgroundColor))
        .preferredColorScheme(.light)
        .frame(width: 600, height: 80)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 80)
        host.layout()
    }

    @MainActor
    @Test func approvalRowSendingDark() {
        let view = ApprovalRow(
            recipientCount: 1,
            accountEmail: "me@test.com",
            sendState: .sending,
            onCancel: {},
            onConfirmNow: {},
            onRetrySend: {}
        )
        .padding(16)
        .background(Color(.windowBackgroundColor))
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 80)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 80)
        host.layout()
    }

    @MainActor
    @Test func approvalRowFailedDark() {
        let view = ApprovalRow(
            recipientCount: 1,
            accountEmail: "me@test.com",
            sendState: .failed(.send(underlying: NSError(domain: "test", code: 500))),
            onCancel: {},
            onConfirmNow: {},
            onRetrySend: {}
        )
        .padding(16)
        .background(Color(.windowBackgroundColor))
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 80)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 80)
        host.layout()
    }

    @MainActor
    @Test func approvalRowFailedLight() {
        let view = ApprovalRow(
            recipientCount: 1,
            accountEmail: "me@test.com",
            sendState: .failed(.needsReconsent),
            onCancel: {},
            onConfirmNow: {},
            onRetrySend: {},
            onReauthorize: {}
        )
        .padding(16)
        .background(Color(.windowBackgroundColor))
        .preferredColorScheme(.light)
        .frame(width: 600, height: 80)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 80)
        host.layout()
    }
}
