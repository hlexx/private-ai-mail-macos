import AIKit
import AppKit
@testable import ComposeFeature
import GRDB
import MailDomain
import Persistence
import SwiftUI
import Testing

@Suite("ComposeFeature")
struct ComposeFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ComposeFeature.moduleName == "ComposeFeature")
    }
}

// MARK: - ReplyStore generateIfNeeded Tests

@Suite("ReplyStore.generateIfNeeded")
struct ReplyStoreGenerateIfNeededTests {

    private final class CountingAIService: AIService, @unchecked Sendable {
        private(set) var callCount = 0

        func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
            AIThreadBrief(summary: "test", confidence: 0.9)
        }

        func draftReply(
            _ input: AIThreadInput,
            tone: AIReplyTone,
            locale: Locale,
            replyLanguage: String?
        ) async throws -> AIThreadReply {
            callCount += 1
            return AIThreadReply(body: "Reply", confidence: 0.9)
        }
    }

    private struct FailingAIService: AIService {
        func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
            AIThreadBrief(summary: "test", confidence: 0.9)
        }

        func draftReply(
            _ input: AIThreadInput,
            tone: AIReplyTone,
            locale: Locale,
            replyLanguage: String?
        ) async throws -> AIThreadReply {
            throw AIError.invalidStructuredOutput("malformed")
        }
    }

    private struct PlaceholderAIService: AIService {
        func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
            AIThreadBrief(summary: "test", confidence: 0.9)
        }

        func draftReply(
            _ input: AIThreadInput,
            tone: AIReplyTone,
            locale: Locale,
            replyLanguage: String?
        ) async throws -> AIThreadReply {
            AIThreadReply(body: "...", evidenceMessageIDs: ["msg1"], confidence: 0.9)
        }
    }

    private final class MutableAIService: AIService, @unchecked Sendable {
        private(set) var callCount = 0
        var error: (any Error)?

        func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
            AIThreadBrief(summary: "test", confidence: 0.9)
        }

        func draftReply(
            _ input: AIThreadInput,
            tone: AIReplyTone,
            locale: Locale,
            replyLanguage: String?
        ) async throws -> AIThreadReply {
            callCount += 1
            if let error {
                throw error
            }
            return AIThreadReply(body: "Reply \(callCount)", confidence: 0.9)
        }
    }

    private func makeDB() async throws -> AppDatabase {
        let db = try AppDatabase.openInMemorySync()
        try await db.dbQueue.write { database in
            try database.execute(sql: """
                INSERT INTO account (id, email, provider, display_name, created_at)
                VALUES ('acc1', 'test@example.com', 'gmail', 'Test', 1000)
            """)
            try database.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count)
                VALUES ('t1', 'acc1', 'Test', 'Hello', 1000, 1)
            """)
            try database.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, sent_at, body_text, flags)
                VALUES ('msg1', 't1', 'acc1', 'alice@test.com', 1000, 'Hello', 0)
            """)
        }
        return db
    }

    @MainActor
    @Test func generateIfNeededCallsGenerateOnCacheMiss() async throws {
        let mock = CountingAIService()
        let db = try await makeDB()
        let store = ReplyStore(aiService: mock, db: db)

        store.generateIfNeeded(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(500))
        #expect(mock.callCount == 1)

        // Second call should be a no-op (cached)
        let focusRequestsBeforeCacheHit = store.focusRequestCount
        store.generateIfNeeded(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(200))
        #expect(mock.callCount == 1) // Not called again
        #expect(store.focusRequestCount == focusRequestsBeforeCacheHit + 1)
    }

    @MainActor
    @Test func generateIfNeededSkipsWhenCached() async throws {
        let store = ReplyStore()
        // Preview store has no AI service, should not crash
        store.generateIfNeeded(threadID: "t1", tone: .warm, replyLanguage: "en")
        #expect(store.reply == nil)
    }

    @MainActor
    @Test func prepareForDisplayDoesNotGenerateOnCacheMiss() async throws {
        let mock = CountingAIService()
        let db = try await makeDB()
        let store = ReplyStore(aiService: mock, db: db)

        let displayedDraft = store.prepareForDisplay(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(200))

        #expect(displayedDraft == false)
        #expect(mock.callCount == 0)
        #expect(store.reply == nil)
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func prepareForDisplayShowsCachedDraftWithoutGenerating() async throws {
        let mock = CountingAIService()
        let db = try await makeDB()
        let store = ReplyStore(aiService: mock, db: db)

        store.generateIfNeeded(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(500))
        #expect(mock.callCount == 1)

        store.generate(threadID: "t1", tone: .direct, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(500))
        #expect(mock.callCount == 2)

        let focusRequestsBeforeCacheHit = store.focusRequestCount
        let displayedDraft = store.prepareForDisplay(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(200))

        #expect(displayedDraft == true)
        #expect(mock.callCount == 2)
        #expect(store.reply?.body == "Reply")
        #expect(store.focusRequestCount == focusRequestsBeforeCacheHit + 1)
    }

    @MainActor
    @Test func generateIfNeededCacheHitClearsStaleErrorAndLoadingState() async throws {
        let ai = MutableAIService()
        let db = try await makeDB()
        let store = ReplyStore(aiService: ai, db: db)

        store.generateIfNeeded(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(500))
        #expect(ai.callCount == 1)
        #expect(store.reply?.body == "Reply 1")

        ai.error = AIError.invalidStructuredOutput("malformed")
        store.generate(threadID: "t1", tone: .direct, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(500))
        #expect(ai.callCount == 2)
        #expect(store.reply == nil)
        #expect(store.error != nil)

        let focusRequestsBeforeCacheHit = store.focusRequestCount
        store.generateIfNeeded(threadID: "t1", tone: .warm, replyLanguage: "en")

        #expect(ai.callCount == 2)
        #expect(store.reply?.body == "Reply 1")
        #expect(store.error == nil)
        #expect(store.isLoading == false)
        #expect(store.focusRequestCount == focusRequestsBeforeCacheHit + 1)
    }

    @MainActor
    @Test func inlineComposerDoesNotGenerateOnAppear() async throws {
        let mock = CountingAIService()
        let db = try await makeDB()
        let store = ReplyStore(aiService: mock, db: db)
        let view = InlineComposer(threadID: "t1", replyStore: store)
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .frame(width: 600, height: 400)
        let host = NSHostingView(rootView: view)

        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layout()
        try await Task.sleep(for: .milliseconds(300))

        #expect(mock.callCount == 0)
        #expect(store.reply == nil)
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func inlineComposerExternalDraftRequestStartsDraftingOnAppear() async throws {
        let mock = CountingAIService()
        let db = try await makeDB()
        let store = ReplyStore(aiService: mock, db: db)
        let view = InlineComposer(threadID: "t1", draftRequestID: 1, replyStore: store)
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .frame(width: 600, height: 400)
        let host = NSHostingView(rootView: view)

        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layout()
        try await Task.sleep(for: .milliseconds(500))

        #expect(mock.callCount == 1)
        #expect(store.reply?.body == "Reply")
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func inlineComposerExplicitGenerationActionStartsDrafting() async throws {
        let mock = CountingAIService()
        let db = try await makeDB()
        let store = ReplyStore(aiService: mock, db: db)
        let composer = InlineComposer(threadID: "t1", replyStore: store)

        composer.requestDraftGeneration(force: false)
        try await Task.sleep(for: .milliseconds(500))

        #expect(mock.callCount == 1)
        #expect(store.reply?.body == "Reply")
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func inlineComposerRegenerateActionPreservesExplicitDraftWorkflow() async throws {
        let mock = CountingAIService()
        let db = try await makeDB()
        let store = ReplyStore(aiService: mock, db: db)
        let composer = InlineComposer(threadID: "t1", replyStore: store)

        composer.requestDraftGeneration(force: false)
        try await Task.sleep(for: .milliseconds(500))
        composer.requestDraftGeneration(force: true)
        try await Task.sleep(for: .milliseconds(500))

        #expect(mock.callCount == 2)
        #expect(store.reply?.body == "Reply")
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func generateShowsFailureStateWhenAIServiceThrows() async throws {
        let db = try await makeDB()
        let store = ReplyStore(aiService: FailingAIService(), db: db)

        store.generate(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(500))

        #expect(store.reply == nil)
        #expect(store.error != nil)
        #expect(store.isLoading == false)
    }

    @Test func displayableDraftRejectsPlaceholders() {
        #expect(!ReplyStore.isDisplayableDraft("..."))
        #expect(!ReplyStore.isDisplayableDraft("type"))
        #expect(!ReplyStore.isDisplayableDraft(" body "))
        #expect(ReplyStore.isDisplayableDraft("Thanks, I will review this."))
    }

    @MainActor
    @Test func generateRejectsPlaceholderDraftBody() async throws {
        let db = try await makeDB()
        let store = ReplyStore(aiService: PlaceholderAIService(), db: db)

        store.generate(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .seconds(1))

        #expect(store.reply == nil)
        #expect(store.error != nil)
        #expect(store.isLoading == false)
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

    @MainActor
    @Test func inlineComposerWithDraftError() {
        let store = ReplyStore.preview(error: AIError.invalidStructuredOutput("malformed"))
        let view = InlineComposer(threadID: "t1", replyStore: store)
            .padding(24)
            .background(Color(.windowBackgroundColor))
            .preferredColorScheme(.light)
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
