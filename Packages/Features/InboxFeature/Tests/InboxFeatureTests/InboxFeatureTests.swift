import ActionsFeature
import Testing
import SwiftUI
import AppKit
@testable import InboxFeature
import DesignSystem
import MailDomain
import Persistence

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

    @Test func folderIDsExposeCanonicalMailboxAndGmailLabelMapping() {
        #expect(FolderID.inbox.canonicalMailbox == .inbox)
        #expect(FolderID.sent.canonicalMailbox == .sent)
        #expect(FolderID.starred.canonicalMailbox == .starred)
        #expect(FolderID.trash.canonicalMailbox == .trash)
        #expect(FolderID.spam.canonicalMailbox == .spam)
        #expect(FolderID.archive.canonicalMailbox == .archive)

        #expect(FolderID.inbox.gmailLabel == "INBOX")
        #expect(FolderID.sent.gmailLabel == "SENT")
        #expect(FolderID.starred.gmailLabel == "STARRED")
        #expect(FolderID.trash.gmailLabel == "TRASH")
        #expect(FolderID.spam.gmailLabel == "SPAM")
        #expect(FolderID.archive.gmailLabel == nil)
        #expect(FolderID.needsReply.gmailLabel == nil)
    }

    // MARK: - Trust MVP Actions

    @MainActor
    @Test func lowRiskActionQueuesAndCompletesWithoutApproval() async {
        let queue = TestTrustActionQueue(outcomes: [
            .init(opId: "req-archive", status: .completed, message: "Action completed"),
        ])
        let store = TrustActionUIStore(queue: queue)

        await store.requestAction(TrustActionRequest(
            requestId: "req-archive",
            action: .archiveThread,
            target: .init(accountId: "a1", threadId: "t1", subject: "Subject")
        ))

        #expect(store.pendingApproval == nil)
        #expect(store.outboxItems.first?.status == .completed)
        #expect(queue.started.map(\.action) == [.archiveThread])
    }

    @MainActor
    @Test func retryAffordanceOnlyRunsForRetryableFailure() async {
        let queue = TestTrustActionQueue(
            outcomes: [
                .init(opId: "req-mark-read", status: .failedRetryable, message: "Network is unavailable. Retry when the connection returns."),
            ],
            retryOutcomes: [
                "req-mark-read": .init(opId: "req-mark-read", status: .completed, message: "Action completed"),
            ]
        )
        let store = TrustActionUIStore(queue: queue)

        await store.requestAction(TrustActionRequest(
            requestId: "req-mark-read",
            action: .markRead,
            target: .init(accountId: "a1", threadId: "t1")
        ))
        #expect(store.outboxItems.first?.canRetry == true)

        await store.retry(opId: "req-mark-read")

        #expect(store.outboxItems.first?.status == .completed)
        #expect(queue.retried == ["req-mark-read"])
    }

    @MainActor
    @Test func completedAndNonRetryableActionsDoNotRetry() async {
        let queue = TestTrustActionQueue(outcomes: [])
        let store = TrustActionUIStore(queue: queue)
        store.replaceOutboxItems([
            .init(
                id: "done",
                action: .archiveThread,
                target: .init(accountId: "a1", threadId: "t1"),
                status: .completed,
                message: "Action completed"
            ),
            .init(
                id: "failed",
                action: .trashThread,
                target: .init(accountId: "a1", threadId: "t2"),
                status: .failedNonRetryable,
                message: "The provider rejected this action."
            ),
        ])

        await store.retry(opId: "done")
        await store.retry(opId: "failed")

        #expect(queue.retried.isEmpty)
    }

    @MainActor
    @Test func retryReturningNilRestoresRetryableFailureState() async {
        let queue = TestTrustActionQueue(outcomes: [], retryOutcomes: [:])
        let store = TrustActionUIStore(queue: queue)
        store.replaceOutboxItems([
            .init(
                id: "retryable",
                action: .archiveThread,
                target: .init(accountId: "a1", threadId: "t1"),
                status: .failedRetryable,
                failureKind: .networkUnavailable,
                message: "Network is unavailable. Retry when the connection returns."
            ),
        ])

        await store.retry(opId: "retryable")

        #expect(store.outboxItems.first?.status == .failedRetryable)
        #expect(store.outboxItems.first?.failureKind == .networkUnavailable)
        #expect(store.outboxItems.first?.message == "Network is unavailable. Retry when the connection returns.")
        #expect(queue.retried == ["retryable"])
    }

    @MainActor
    @Test func aiGeneratedActionOutputIsNotQueuedAutomatically() async {
        let queue = TestTrustActionQueue(outcomes: [])
        let store = TrustActionUIStore(queue: queue)

        await store.requestAction(TrustActionRequest(
            requestId: "ai-output",
            action: .archiveThread,
            target: .init(accountId: "a1", threadId: "t1"),
            createdByAIOutput: true
        ))

        #expect(store.pendingApproval == nil)
        #expect(store.outboxItems.isEmpty)
        #expect(queue.started.isEmpty)
    }

    @MainActor
    @Test func draftReplyContextActionUsesInlineDraftCallback() async throws {
        let queue = TestTrustActionQueue(outcomes: [
            .init(opId: "draft-provider", status: .completed, message: "Provider draft queued"),
        ])
        let actionStore = TrustActionUIStore(queue: queue)
        var requestedThread: (threadId: String, accountId: String)?
        let view = InboxView(
            store: InboxStore(db: try AppDatabase.openInMemorySync(), searchService: nil),
            actionStore: actionStore,
            onDraftReply: { threadId, accountId in
                requestedThread = (threadId, accountId)
            }
        )
        let thread = ThreadRow(
            record: ThreadRecord(
                id: "t1",
                accountId: "a1",
                subject: "Subject",
                snippet: "Snippet",
                lastMessageAt: 1,
                messageCount: 1
            ),
            latestFromAddr: "sender@example.com"
        )

        view.requestDraftReply(for: thread)
        try await Task.sleep(for: .milliseconds(100))

        #expect(requestedThread?.threadId == "t1")
        #expect(requestedThread?.accountId == "a1")
        #expect(actionStore.pendingApproval == nil)
        #expect(actionStore.outboxItems.isEmpty)
        #expect(queue.started.isEmpty)
    }
}

@MainActor
private final class TestTrustActionQueue: TrustActionQueueing {
    private var outcomes: [TrustActionQueueOutcome]
    private let retryOutcomes: [String: TrustActionQueueOutcome]
    private(set) var started: [TrustActionRequest] = []
    private(set) var retried: [String] = []

    init(
        outcomes: [TrustActionQueueOutcome],
        retryOutcomes: [String: TrustActionQueueOutcome] = [:]
    ) {
        self.outcomes = outcomes
        self.retryOutcomes = retryOutcomes
    }

    func start(_ request: TrustActionRequest) async -> TrustActionQueueOutcome {
        started.append(request)
        if !outcomes.isEmpty {
            return outcomes.removeFirst()
        }
        return TrustActionQueueOutcome(
            opId: request.requestId,
            status: .completed,
            message: "Action completed"
        )
    }

    func retry(opId: String) async -> TrustActionQueueOutcome? {
        retried.append(opId)
        return retryOutcomes[opId]
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
