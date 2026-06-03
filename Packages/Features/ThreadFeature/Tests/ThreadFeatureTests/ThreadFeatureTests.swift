import ActionsFeature
import Testing
import SwiftUI
import AppKit
import AIKit
import AttachmentRAG
@testable import ThreadFeature
import DesignSystem
import Persistence

@Suite("ThreadFeature")
struct ThreadFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ThreadFeature.moduleName == "ThreadFeature")
    }

    @Test func compactActionTargetsUseCompactHitSize() {
        #expect(ThreadActionMetrics.compactTargetSize >= RBControlMetrics.compactHitTarget)
        #expect(ThreadBottomPanelMetrics.tabMinHeight >= RBControlMetrics.compactHitTarget)
        #expect(ThreadBottomPanelMetrics.collapseButtonMinSize >= RBControlMetrics.compactHitTarget)
    }

    // MARK: - MessageRow

    @Test func messageRowExtractsNameFromDisplayFormat() {
        let name = MessageRow.extractName(from: "Marta Kowalski <marta@example.com>")
        #expect(name == "Marta Kowalski")
    }

    @Test func messageRowExtractsNameFromBareEmail() {
        let name = MessageRow.extractName(from: "alex@studio.eu")
        #expect(name == "alex")
    }

    @Test func messageRowExtractsNameFromEmptyString() {
        let name = MessageRow.extractName(from: "")
        #expect(name == "?")
    }

    @Test func messageRowExtractsNameWithQuotes() {
        let name = MessageRow.extractName(from: "\"Jonas R.\" <jonas@example.com>")
        #expect(name == "Jonas R.")
    }

    @Test func messageRowExposesBodyHtml() {
        let record = MessageRecord(
            id: "m1", threadId: "t1", accountId: "a1",
            sentAt: 1_700_000_000,
            bodyHtml: "<p>Hello</p>",
            bodyText: nil
        )
        let row = MessageRow(record: record)
        #expect(row.bodyHtml == "<p>Hello</p>")
        #expect(row.bodyText == "") // falls back to snippet (nil) -> ""
    }

    // MARK: - HTML to Plain Text

    @MainActor @Test func htmlToPlainTextExtractsContent() {
        let html = "<html><body><p>Hello <b>World</b></p><p>Second paragraph</p></body></html>"
        let plain = MessageBodyView.htmlToPlainText(html)
        #expect(plain != nil)
        #expect(plain!.contains("Hello"))
        #expect(plain!.contains("World"))
        #expect(plain!.contains("Second paragraph"))
    }

    @MainActor @Test func htmlToPlainTextStripsExcessiveNewlines() {
        let html = "<p>A</p><br><br><br><br><p>B</p>"
        let plain = MessageBodyView.htmlToPlainText(html)
        #expect(plain != nil)
        // Should not contain 3+ consecutive newlines
        #expect(!plain!.contains("\n\n\n"))
    }

    @MainActor @Test func htmlToPlainTextReturnsNilForEmpty() {
        let result = MessageBodyView.htmlToPlainText("")
        // Empty HTML may return nil or empty string
        #expect(result == nil || result!.isEmpty)
    }

    @MainActor @Test func htmlToPlainTextStripsStyleBlocks() {
        let html = """
        <html><head><style type="text/css">
        body, table, td { font-family: Arial, Helvetica, sans-serif !important; }
        .mso-line-height-rule { mso-line-height-rule: exactly; }
        </style></head><body><h1>Summer Sale</h1><p>20% off all items</p></body></html>
        """
        let plain = MessageBodyView.htmlToPlainText(html)
        #expect(plain != nil)
        #expect(plain!.contains("Summer Sale"))
        #expect(plain!.contains("20% off"))
        #expect(!plain!.contains("font-family"))
        #expect(!plain!.contains("mso-line-height-rule"))
        #expect(!plain!.contains("Arial"))
    }

    @MainActor @Test func htmlToPlainTextStripsScriptBlocks() {
        let html = """
        <html><body>
        <script>var tracking = { id: "abc123" };</script>
        <p>Hello World</p>
        <script type="text/javascript">console.log("track");</script>
        </body></html>
        """
        let plain = MessageBodyView.htmlToPlainText(html)
        #expect(plain != nil)
        #expect(plain!.contains("Hello World"))
        #expect(!plain!.contains("tracking"))
        #expect(!plain!.contains("console.log"))
    }

    // MARK: - AttachmentInfo

    @Test func attachmentFormattedSizeKB() {
        let info = AttachmentInfo(id: "a1", filename: "test.pdf", sizeBytes: 284_000, mime: "application/pdf")
        #expect(info.formattedSize == "277 KB")
    }

    @Test func attachmentFormattedSizeMB() {
        let info = AttachmentInfo(id: "a2", filename: "large.zip", sizeBytes: 2_500_000, mime: nil)
        #expect(info.formattedSize == "2.4 MB")
    }

    @Test func attachmentFormattedSizeNil() {
        let info = AttachmentInfo(id: "a3", filename: "unknown", sizeBytes: nil, mime: nil)
        #expect(info.formattedSize == "")
    }

    @Test func attachmentStatusCopyCoversSummaryStates() {
        let attachment = AttachmentInfo(
            id: "att1",
            messageId: "m1",
            accountId: "a1",
            filename: "invoice.txt",
            sizeBytes: 284_000,
            mime: "text/plain"
        )
        let generatedSummary = AttachmentSummaryViewData(
            summary: AIAttachmentSummary(summary: "Attachment summary", confidence: 0.9),
            cached: false
        )
        let cachedSummary = AttachmentSummaryViewData(
            summary: AIAttachmentSummary(summary: "Attachment summary", confidence: 0.9),
            cached: true
        )

        #expect(AttachmentSummaryCopy.statusText(for: attachment, state: .idle) == "277 KB \u{00B7} ready to summarize")
        #expect(AttachmentSummaryCopy.statusText(for: attachment, state: .summarizing) == "277 KB \u{00B7} summarizing locally")
        #expect(
            AttachmentSummaryCopy.statusText(for: attachment, state: .summary(generatedSummary))
                == "277 KB \u{00B7} summarized locally"
        )
        #expect(
            AttachmentSummaryCopy.statusText(for: attachment, state: .summary(cachedSummary))
                == "277 KB \u{00B7} cached local summary"
        )
        #expect(
            AttachmentSummaryCopy.statusText(for: attachment, state: .unsupported("Unsupported"))
                == "277 KB \u{00B7} unsupported"
        )
        #expect(
            AttachmentSummaryCopy.statusText(for: attachment, state: .failed("Failed"))
                == "277 KB \u{00B7} summary failed"
        )
    }

    @MainActor @Test func attachmentSummaryStoreShowsSummary() async throws {
        let db = try makeAttachmentSummaryDatabase()
        let provider = TestAttachmentByteProvider(data: Data("Amount due: EUR 1840".utf8))
        let ai = TestAttachmentAIService()
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: provider
        )
        let store = AttachmentSummaryStore(orchestrator: orchestrator)
        let attachment = AttachmentInfo(
            id: "att1",
            messageId: "m1",
            accountId: "a1",
            filename: "invoice.txt",
            sizeBytes: 10,
            mime: "text/plain"
        )

        #expect(store.state(for: attachment) == .idle)
        store.summarize(attachment)
        #expect(store.state(for: attachment).isWorking)

        let finalState = try await waitForAttachmentState(store: store, attachment: attachment) { state in
            if case .summary = state { return true }
            return false
        }

        guard case .summary(let summary) = finalState else {
            Issue.record("Expected summary state")
            return
        }
        #expect(summary.summary == "Attachment summary")
        #expect(summary.cached == false)
        #expect(await ai.callCount == 1)
    }

    @MainActor @Test func attachmentSummaryStoreShowsUnsupportedState() async throws {
        let db = try makeAttachmentSummaryDatabase(mime: "application/zip", filename: "archive.zip")
        let provider = TestAttachmentByteProvider(data: Data([0x00, 0x01]))
        let ai = TestAttachmentAIService()
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: provider
        )
        let store = AttachmentSummaryStore(orchestrator: orchestrator)
        let attachment = AttachmentInfo(
            id: "att1",
            messageId: "m1",
            accountId: "a1",
            filename: "archive.zip",
            sizeBytes: 2,
            mime: "application/zip"
        )

        store.summarize(attachment)
        let finalState = try await waitForAttachmentState(store: store, attachment: attachment) { state in
            if case .unsupported = state { return true }
            return false
        }

        guard case .unsupported(let reason) = finalState else {
            Issue.record("Expected unsupported state")
            return
        }
        #expect(reason.contains("Unsupported"))
        #expect(await ai.callCount == 0)
    }

    // MARK: - Trust MVP Actions

    @MainActor
    @Test func draftReplyRequiresExplicitApprovalBeforeQueueing() async {
        let queue = ThreadTrustActionQueue(outcome: .init(
            opId: "draft-1",
            status: .completed,
            message: "Draft action approved"
        ))
        let store = TrustActionUIStore(queue: queue)

        await store.requestAction(TrustActionRequest(
            requestId: "draft-1",
            action: .draftReply,
            target: .init(accountId: "a1", threadId: "t1")
        ))

        #expect(store.pendingApproval?.request.action == .draftReply)
        #expect(store.outboxItems.isEmpty)

        await store.confirmPendingAction()

        #expect(store.pendingApproval == nil)
        #expect(store.outboxItems.first?.status == .completed)
        #expect(queue.started.map(\.action) == [.draftReply])
    }

    @MainActor
    @Test func destructiveTrashRequiresApprovalAndCanFailRetryable() async {
        let queue = ThreadTrustActionQueue(outcome: .init(
            opId: "trash-1",
            status: .failedRetryable,
            message: "Network is unavailable. Retry when the connection returns."
        ))
        let store = TrustActionUIStore(queue: queue)

        await store.requestAction(TrustActionRequest(
            requestId: "trash-1",
            action: .trashThread,
            target: .init(accountId: "a1", threadId: "t1")
        ))
        #expect(store.pendingApproval?.request.action == .trashThread)

        await store.confirmPendingAction()

        #expect(store.outboxItems.first?.status == .failedRetryable)
        #expect(store.outboxItems.first?.canRetry == true)
    }

    @MainActor
    @Test func nonRetryableFailureDoesNotExposeRetry() async {
        let queue = ThreadTrustActionQueue(outcome: .init(
            opId: "star-1",
            status: .failedNonRetryable,
            message: "The account is missing permission for this action."
        ))
        let store = TrustActionUIStore(queue: queue)

        await store.requestAction(TrustActionRequest(
            requestId: "star-1",
            action: .starThread,
            target: .init(accountId: "a1", threadId: "t1")
        ))

        #expect(store.outboxItems.first?.status == .failedNonRetryable)
        #expect(store.outboxItems.first?.canRetry == false)
    }
}

@MainActor
private final class ThreadTrustActionQueue: TrustActionQueueing {
    let outcome: TrustActionQueueOutcome
    private(set) var started: [TrustActionRequest] = []

    init(outcome: TrustActionQueueOutcome) {
        self.outcome = outcome
    }

    func start(_ request: TrustActionRequest) async -> TrustActionQueueOutcome {
        started.append(request)
        return outcome
    }

    func retry(opId _: String) async -> TrustActionQueueOutcome? {
        nil
    }
}

private func makeAttachmentSummaryDatabase(
    mime: String = "text/plain",
    filename: String = "invoice.txt"
) throws -> AppDatabase {
    let db = try AppDatabase.openInMemorySync()
    try db.dbQueue.write { database in
        try AccountRecord(id: "a1", email: "a@example.com", createdAt: 1).insert(database)
        try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 1).insert(database)
        try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 1).insert(database)
        try AttachmentRecord(
            id: "att1",
            messageId: "m1",
            accountId: "a1",
            filename: filename,
            mime: mime,
            sizeBytes: 10
        ).insert(database)
    }
    return db
}

@MainActor
private func waitForAttachmentState(
    store: AttachmentSummaryStore,
    attachment: AttachmentInfo,
    matches: (AttachmentSummaryViewState) -> Bool
) async throws -> AttachmentSummaryViewState {
    for _ in 0..<50 {
        let state = store.state(for: attachment)
        if matches(state) { return state }
        try await Task.sleep(for: .milliseconds(20))
    }
    return store.state(for: attachment)
}

private struct TestAttachmentByteProvider: AttachmentByteProvider {
    let data: Data

    func fetchAttachmentData(accountId _: String, messageId _: String, attachmentId _: String) async throws -> Data {
        data
    }
}

private actor TestAttachmentAIService: AIService {
    private(set) var callCount = 0

    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        AIThreadBrief(summary: "unused", confidence: 0.1)
    }

    func draftReply(
        _ input: AIThreadInput,
        tone _: AIReplyTone,
        locale _: Locale,
        replyLanguage _: String?
    ) async throws -> AIThreadReply {
        AIThreadReply(body: "unused")
    }

    func attachmentSummary(_ input: AIAttachmentSummaryInput) async throws -> AIAttachmentSummary {
        callCount += 1
        return AIAttachmentSummary(
            summary: "Attachment summary",
            keyFields: [AIKeyField(name: "amount", value: "EUR 1840")],
            risks: [],
            nextSteps: ["Pay invoice"],
            evidence: [AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840")],
            confidence: 0.9
        )
    }
}

// MARK: - Snapshot Tests

@Suite("ThreadView Snapshots")
@MainActor
struct ThreadViewSnapshotTests {

    @MainActor
    @Test func emptyStateDark() {
        let view = emptyStateView()
            .preferredColorScheme(.dark)
            .frame(width: 700, height: 500)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    @MainActor
    @Test func emptyStateLight() {
        let view = emptyStateView()
            .preferredColorScheme(.light)
            .frame(width: 700, height: 500)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    @MainActor
    @Test func messageCardDark() {
        let view = messageCardView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.layout()
    }

    @MainActor
    @Test func messageCardLight() {
        let view = messageCardView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.layout()
    }

    @MainActor
    @Test func attachmentBlockDark() {
        let view = attachmentBlockView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 100)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        host.layout()
    }

    @MainActor
    @Test func attachmentBlockLight() {
        let view = attachmentBlockView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 100)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        host.layout()
    }

    @MainActor
    @Test func headSectionDark() {
        let view = headSectionView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 140)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 140)
        host.layout()
    }

    @MainActor
    @Test func headSectionLight() {
        let view = headSectionView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 140)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 140)
        host.layout()
    }

    @MainActor
    @Test func threadViewRendersComposerWithLongMessage() async throws {
        let db = try makeThreadViewDatabase()
        let store = ThreadStore(db: db)
        store.accountEmail = "alex@example.com"
        store.observe(threadId: "t1", accountId: "acc1")
        try await waitUntil { !store.messages.isEmpty }

        let view = ThreadView(
            store: store,
            composer: {
                Text("Draft reply panel")
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(Color.rbBgElev1)
            },
            briefRail: {
                EmptyView()
            }
        )
        .preferredColorScheme(.light)
        .frame(width: 900, height: 700)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        host.layout()
    }

    private func emptyStateView() -> some View {
        VStack(spacing: 8) {
            Text("Re:")
                .font(.rbSerifItalic(48))
                .foregroundStyle(Color.rbFg3)
            Text("Select a thread")
                .rbTextStyle(.h3)
                .foregroundStyle(Color.rbFg1)
            Text("Re:Box will brief you the moment you open it.")
                .rbTextStyle(.body)
                .foregroundStyle(Color.rbFg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgCanvas)
    }

    private func messageCardView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                AvatarView(name: "Marta Kowalski", size: 28)
                Text("Marta Kowalski")
                    .font(.rbGeist(13, weight: .semibold))
                    .foregroundStyle(Color.rbFg1)
                Spacer()
                Text("Mon 14:30")
                    .font(.rbMono(11))
                    .foregroundStyle(Color.rbFg3)
            }
            Text("Hi — yes, I'll send a clean draft by Friday EOD.")
                .font(.rbGeist(14))
                .foregroundStyle(Color.rbFg2)
                .lineSpacing(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.md)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
        .padding(20)
        .background(Color.rbBgCanvas)
    }

    private func attachmentBlockView() -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: RBRadius.xs)
                .fill(Color.rbBgElev2)
                .frame(width: 38, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("contract.pdf")
                    .font(.rbGeist(13, weight: .medium))
                    .foregroundStyle(Color.rbFg1)
                Text("277 KB · summarized locally")
                    .font(.rbMono(11))
                    .foregroundStyle(Color.rbFg3)
            }
            Spacer()
            Button("Preview") {}
                .buttonStyle(.rbGhost)
            Button("Summarize") {}
                .buttonStyle(.rbSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .padding(20)
        .background(Color.rbBgCanvas)
    }

    @MainActor
    @Test func messageBodyPlainTextDark() {
        let view = MessageBodyView(
            bodyHtml: nil,
            bodyText: "Hi — yes, I'll send a clean draft by Friday EOD.",
            snippet: "Hi",
            attachments: []
        )
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 100)
        .background(Color.rbBgElev1)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        host.layout()
    }

    @MainActor
    @Test func messageBodyHtmlDark() {
        let html = "<p>Hello <b>World</b></p><p>This is an <a href='#'>HTML</a> email.</p>"
        let view = MessageBodyView(
            bodyHtml: html,
            bodyText: nil,
            snippet: "Hello World",
            attachments: []
        )
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 200)
        .background(Color.rbBgElev1)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.layout()
    }

    @MainActor
    @Test func messageBodyWithRemoteImagesPillDark() {
        let html = """
        <p>Newsletter</p>
        <img src="https://example.com/tracker.png" width="1" height="1">
        <p>Click here for deals</p>
        """
        let view = MessageBodyView(
            bodyHtml: html,
            bodyText: nil,
            snippet: "Newsletter",
            attachments: []
        )
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 250)
        .background(Color.rbBgElev1)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 250)
        host.layout()
    }

    @MainActor
    @Test func messageBodySnippetFallbackLight() {
        let view = MessageBodyView(
            bodyHtml: nil,
            bodyText: nil,
            snippet: "Brief preview of the email...",
            attachments: []
        )
        .preferredColorScheme(.light)
        .frame(width: 600, height: 60)
        .background(Color.rbBgElev1)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }

    private func headSectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Re: Contract approval — Acme GmbH")
                .rbTextStyle(.h2)
                .foregroundStyle(Color.rbFg1)
            HStack(spacing: 8) {
                Text("Marta Kowalski").foregroundStyle(Color.rbFg2)
                Text("·").foregroundStyle(Color.rbFg3)
                Text("to alex@studio.eu").foregroundStyle(Color.rbFg2)
                Text("·").foregroundStyle(Color.rbFg3)
                Text("3 messages").foregroundStyle(Color.rbFg2)
            }
            .font(.rbMono(11))
            HStack(spacing: 8) {
                Spacer()
                Button {} label: { Label("Archive", systemImage: "archivebox") }.buttonStyle(.rbGhost)
                Button {} label: { Label("Snooze", systemImage: "clock") }.buttonStyle(.rbGhost)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.rbBgCanvas)
    }

    private func makeThreadViewDatabase() throws -> AppDatabase {
        let db = try AppDatabase.openInMemorySync()
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO account (id, email, display_name, provider, created_at) VALUES
                ('acc1', 'alex@example.com', 'Alex', 'gmail', 1000)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread) VALUES
                ('t1', 'acc1', 'Long email', 'snippet', 1000, 1, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, to_addr, sent_at, body_text, flags) VALUES
                ('m1', 't1', 'acc1', 'OpenAI <billing@example.com>', 'alex@example.com', 1000, :body, 0)
                """, arguments: ["body": String(repeating: "Long billing update paragraph. ", count: 120)])
        }
        return db
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func starButtonView(isStarred: Bool) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button {} label: { Label("Archive", systemImage: "archivebox") }.buttonStyle(.rbGhost)
            Button {} label: {
                Label(
                    isStarred ? "Unstar" : "Star",
                    systemImage: isStarred ? "star.fill" : "star"
                )
            }.buttonStyle(.rbGhost)
            Button {} label: { Label("Snooze", systemImage: "clock") }.buttonStyle(.rbGhost)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.rbBgCanvas)
    }

    @MainActor
    @Test func starButtonUnstarredDark() {
        let view = starButtonView(isStarred: false)
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }

    @MainActor
    @Test func starButtonUnstarredLight() {
        let view = starButtonView(isStarred: false)
            .preferredColorScheme(.light)
            .frame(width: 600, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }

    @MainActor
    @Test func starButtonStarredDark() {
        let view = starButtonView(isStarred: true)
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }

    @MainActor
    @Test func starButtonStarredLight() {
        let view = starButtonView(isStarred: true)
            .preferredColorScheme(.light)
            .frame(width: 600, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }
}

// MARK: - ThreadStore isStarred Tests

@Suite("ThreadStore Star State")
@MainActor
struct ThreadStoreStarTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.openInMemorySync()
    }

    private func seedThread(db: AppDatabase, starred: Bool) throws {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO account (id, email, display_name, provider, created_at) VALUES
                ('acc1', 'user@example.com', 'User', 'gmail', 1000)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread) VALUES
                ('t1', 'acc1', 'Test Subject', 'snippet', 1000, 1, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, to_addr, sent_at, flags) VALUES
                ('m1', 't1', 'acc1', 'sender@example.com', 'user@example.com', 1000, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO label (id, account_id, name, type, messages_unread_count, messages_total_count) VALUES
                ('INBOX', 'acc1', 'Inbox', 'system', 0, 0),
                ('STARRED', 'acc1', 'Starred', 'system', 0, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 't1', 'INBOX')
                """)
            if starred {
                try dbConn.execute(sql: """
                    INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                    ('acc1', 't1', 'STARRED')
                    """)
            }
        }
    }

    /// Poll until a condition becomes true, or fail after timeout.
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func isStarredTrueWhenSTARREDLabelPresent() async throws {
        let db = try makeDB()
        try seedThread(db: db, starred: true)
        let store = ThreadStore(db: db)
        store.observe(threadId: "t1", accountId: "acc1")
        // Wait for the observation to deliver its first value (messages loaded)
        try await waitUntil { !store.messages.isEmpty }
        try await waitUntil { store.isStarred }
        #expect(store.isStarred == true)
        store.stopObserving()
    }

    @Test func isStarredFalseWhenNoSTARREDLabel() async throws {
        let db = try makeDB()
        try seedThread(db: db, starred: false)
        let store = ThreadStore(db: db)
        store.observe(threadId: "t1", accountId: "acc1")
        // Wait for messages to load (proves observation fired), then assert not starred
        try await waitUntil { !store.messages.isEmpty }
        #expect(store.isStarred == false)
        store.stopObserving()
    }

    @Test func isStarredUpdatesReactivelyOnLabelChange() async throws {
        let db = try makeDB()
        try seedThread(db: db, starred: false)
        let store = ThreadStore(db: db)
        store.observe(threadId: "t1", accountId: "acc1")
        try await waitUntil { !store.messages.isEmpty }
        #expect(store.isStarred == false)

        // Add STARRED label
        try await db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 't1', 'STARRED')
                """)
        }
        try await waitUntil { store.isStarred }
        #expect(store.isStarred == true)

        // Remove STARRED label
        try await db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                DELETE FROM thread_label WHERE account_id = 'acc1' AND thread_id = 't1' AND label_id = 'STARRED'
                """)
        }
        try await waitUntil { !store.isStarred }
        #expect(store.isStarred == false)

        store.stopObserving()
    }

    @Test func stopObservingResetsIsStarred() async throws {
        let db = try makeDB()
        try seedThread(db: db, starred: true)
        let store = ThreadStore(db: db)
        store.observe(threadId: "t1", accountId: "acc1")
        try await waitUntil { !store.messages.isEmpty }
        try await waitUntil { store.isStarred }
        #expect(store.isStarred == true)
        store.stopObserving()
        #expect(store.isStarred == false)
    }
}

// MARK: - CID Image Resolution Tests

@Suite("CID Image Resolution")
@MainActor
struct CIDImageResolutionTests {

    @Test func resolvedHTMLReplacesCidWithDataURL() {
        let cid = "logo@example.com"
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47]) // tiny fake PNG header
        let html = "<html><body><img src=\"cid:\(cid)\"></body></html>"
        let attachments = [HTMLWebView.AttachmentData(contentId: cid, mime: "image/png", data: pngBytes)]
        let resolved = HTMLWebView.resolveCIDReferences(in: html, attachments: attachments)
        #expect(resolved.contains("data:image/png;base64,\(pngBytes.base64EncodedString())"))
        #expect(!resolved.contains("cid:logo@example.com"))
    }

    @Test func resolvedHTMLHandlesAngleBracketCid() {
        let cid = "logo@1.2.3"
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let html = "<img src=\"cid:<\(cid)>\">"
        let attachments = [HTMLWebView.AttachmentData(contentId: cid, mime: "image/png", data: pngBytes)]
        let resolved = HTMLWebView.resolveCIDReferences(in: html, attachments: attachments)
        #expect(resolved.contains("data:image/png;base64,"))
        #expect(!resolved.contains("cid:"))
    }

    @Test func resolvedHTMLIsCaseInsensitive() {
        let cid = "Logo@Example.COM"
        let pngBytes = Data([0x89, 0x50])
        let html = "<img src=\"CID:\(cid)\">"
        let attachments = [HTMLWebView.AttachmentData(contentId: cid, mime: "image/png", data: pngBytes)]
        let resolved = HTMLWebView.resolveCIDReferences(in: html, attachments: attachments)
        #expect(resolved.contains("data:image/png;base64,"))
        #expect(!resolved.contains("CID:"))
    }

    @Test func inlineAttachmentInfoCreation() {
        let att = InlineAttachment(contentId: "img001@mail", mime: "image/jpeg", dataBase64: "iVBORw0KGgo=")
        #expect(att.contentId == "img001@mail")
        #expect(att.mime == "image/jpeg")
        #expect(att.dataBase64 == "iVBORw0KGgo=")
    }

    @Test func messageRowCarriesInlineAttachments() {
        let record = MessageRecord(
            id: "m1", threadId: "t1", accountId: "a1",
            sentAt: 1_700_000_000,
            bodyHtml: "<img src=\"cid:logo@test\">",
            bodyText: nil
        )
        let inlines = [InlineAttachment(contentId: "logo@test", mime: "image/png", dataBase64: "AAAA")]
        let row = MessageRow(record: record, inlineAttachments: inlines)
        #expect(row.inlineAttachments.count == 1)
        #expect(row.inlineAttachments[0].contentId == "logo@test")
    }

    @Test func htmlWebViewAttachmentDataConversion() {
        let inline = InlineAttachment(contentId: "pic@ex", mime: "image/gif", dataBase64: "R0lGODlh")
        let attData = HTMLWebView.AttachmentData(
            contentId: inline.contentId,
            mime: inline.mime,
            data: Data(base64Encoded: inline.dataBase64) ?? Data()
        )
        #expect(attData.contentId == "pic@ex")
        #expect(attData.mime == "image/gif")
        #expect(!attData.data.isEmpty)
    }
}

// MARK: - Translation JS Script Tests

@Suite("HTMLWebView Translation Scripts")
@MainActor
struct HTMLWebViewTranslationScriptTests {

    @Test func extractionJSContainsTreeWalker() {
        let js = HTMLWebView.extractionJS
        #expect(js.contains("createTreeWalker"))
        #expect(js.contains("SHOW_TEXT"))
        #expect(js.contains("txId"))
        #expect(js.contains("txOrig"))
        #expect(js.contains("2000"))
    }

    @Test func extractionJSSkipsStyleAndScriptNodes() {
        let js = HTMLWebView.extractionJS
        #expect(js.contains("SCRIPT"))
        #expect(js.contains("STYLE"))
        #expect(js.contains("NOSCRIPT"))
    }

    @Test func applyTranslationsJSProducesValidScript() {
        let map = ["n0": "Hello", "n1": "World"]
        let js = HTMLWebView.applyTranslationsJS(map: map)
        #expect(!js.isEmpty)
        #expect(js.contains("data-tx-id"))
        #expect(js.contains("textContent"))
        // The map should be serialized as JSON inside the script
        #expect(js.contains("n0"))
        #expect(js.contains("Hello"))
        #expect(js.contains("n1"))
        #expect(js.contains("World"))
    }

    @Test func applyTranslationsJSHandlesEmptyMap() {
        let map: [String: String] = [:]
        let js = HTMLWebView.applyTranslationsJS(map: map)
        #expect(!js.isEmpty)
    }

    @Test func applyTranslationsJSHandlesSpecialCharacters() {
        let map = ["n0": "He said \"hello\" & goodbye", "n1": "Line1\nLine2"]
        let js = HTMLWebView.applyTranslationsJS(map: map)
        #expect(!js.isEmpty)
        // JSON should properly escape the quotes and newlines
        #expect(js.contains("n0"))
    }

    @Test func restoreOriginalsJSUsesDataAttribute() {
        let js = HTMLWebView.restoreOriginalsJS
        #expect(js.contains("data-tx-id"))
        #expect(js.contains("txOrig"))
        #expect(js.contains("textContent"))
    }

    @Test func textNodeStructure() {
        let node = TranslationTextNode(id: "n42", text: "Summer Sale")
        #expect(node.id == "n42")
        #expect(node.text == "Summer Sale")
    }
}
