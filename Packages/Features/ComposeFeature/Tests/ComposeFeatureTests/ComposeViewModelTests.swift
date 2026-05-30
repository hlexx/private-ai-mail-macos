import Testing
import Foundation
import MailDomain
@testable import ComposeFeature

@Suite("ComposeViewModel")
@MainActor
struct ComposeViewModelTests {

    private func makeViewModel(
        sendResult: Result<SentEcho, Error> = .success(SentEcho(messageID: "m1", threadID: "t1", sentAt: Date()))
    ) -> (ComposeViewModel, MockComposeService) {
        let mock = MockComposeService()
        mock.sendResult = sendResult
        let vm = ComposeViewModel(composeServiceFactory: { _ in mock })
        vm.selectedAccountID = "acc1"
        vm.selectedAccountEmail = "me@example.com"
        vm.toField = "recipient@example.com"
        vm.subjectField = "Test Subject"
        vm.bodyText = "Hello"
        return (vm, mock)
    }

    private func makeQueueViewModel(
        queue: MockComposeSendQueue,
        reauthorizeHandler: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) -> ComposeViewModel {
        let vm = ComposeViewModel(
            sendQueueFactory: { _ in queue },
            reauthorizeHandler: reauthorizeHandler
        )
        vm.selectedAccountID = "acc1"
        vm.selectedAccountEmail = "me@example.com"
        vm.accounts = [
            AccountInfo(id: "acc1", email: "me@example.com", displayName: "Me", provider: .gmail)
        ]
        vm.toField = "recipient@example.com"
        vm.subjectField = "Queued Subject"
        vm.bodyText = "Queued body"
        return vm
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(condition())
    }

    @Test func requestSendTransitionsToAwaitingApproval() async {
        let (vm, _) = makeViewModel()
        vm.requestSend()
        if case .awaitingApproval = vm.sendState {
            // OK
        } else {
            Issue.record("Expected awaitingApproval, got \(vm.sendState)")
        }
    }

    @Test func cancelDuringApprovalReturnsToIdle() async {
        let (vm, _) = makeViewModel()
        vm.requestSend()
        vm.cancelSend()
        if case .idle = vm.sendState {
            // OK
        } else {
            Issue.record("Expected idle after cancel, got \(vm.sendState)")
        }
    }

    @Test func cancelPreventsServiceCall() async throws {
        let (vm, mock) = makeViewModel()
        vm.requestSend()
        vm.cancelSend()
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.sendCallCount == 0)
    }

    @Test func replyPrefillSetsToAndSubject() {
        let (vm, _) = makeViewModel()
        vm.prefillReply(
            fromAddr: "sender@example.com",
            subject: "Original Subject",
            threadID: "thread1",
            lastMessageID: "msg1"
        )
        #expect(vm.toField == "sender@example.com")
        #expect(vm.subjectField == "Re: Original Subject")
        #expect(vm.replyContext?.threadID == "thread1")
        #expect(vm.replyContext?.inReplyToMessageID == "msg1")
    }

    @Test func replyPrefillDeduplicatesRePrefix() {
        let (vm, _) = makeViewModel()
        vm.prefillReply(
            fromAddr: "sender@example.com",
            subject: "Re: Already prefixed",
            threadID: "thread1",
            lastMessageID: "msg1"
        )
        #expect(vm.subjectField == "Re: Already prefixed")
    }

    @Test func deduplicateRePrefixVariants() {
        #expect(ComposeViewModel.deduplicateRePrefix("Hello") == "Re: Hello")
        #expect(ComposeViewModel.deduplicateRePrefix("Re: Hello") == "Re: Hello")
        #expect(ComposeViewModel.deduplicateRePrefix("re: Hello") == "re: Hello")
        #expect(ComposeViewModel.deduplicateRePrefix("RE: Hello") == "RE: Hello")
    }

    @Test func recipientCountParsesCommaSeparated() {
        let (vm, _) = makeViewModel()
        vm.toField = "a@b.com, c@d.com"
        vm.ccField = "e@f.com"
        #expect(vm.recipientCount == 3)
    }

    @Test func recipientCountEmptyIsZero() {
        let (vm, _) = makeViewModel()
        vm.toField = ""
        vm.ccField = ""
        #expect(vm.recipientCount == 0)
    }

    @Test func queuedSendEnqueuesDraftAndMarksSent() async throws {
        let queue = MockComposeSendQueue(statuses: [.sent])
        let vm = makeQueueViewModel(queue: queue)

        vm.requestSend()
        vm.confirmSendNow()
        try await waitUntil {
            if case .sent = vm.sendState {
                return true
            }
            return false
        }

        #expect(queue.enqueueCallCount == 1)
        #expect(queue.executeCallCount == 1)
        #expect(queue.lastDraft?.provider == .gmail)
        #expect(queue.lastDraft?.accountID == "acc1")
        #expect(queue.lastDraft?.subject == "Queued Subject")
        #expect(queue.lastDraft?.bodyText == "Queued body")
        if case .sent = vm.sendState {
            // OK
        } else {
            Issue.record("Expected sent, got \(vm.sendState)")
        }
    }

    @Test func canRequestSendIsFalseWhileQueueOwnsTheSend() {
        let queue = MockComposeSendQueue()
        let vm = makeQueueViewModel(queue: queue)

        vm.sendState = .pending
        #expect(!vm.canRequestSend)
        vm.sendState = .sending
        #expect(!vm.canRequestSend)
        vm.sendState = .retrying
        #expect(!vm.canRequestSend)
        vm.sendState = .needsReconsent
        #expect(!vm.canRequestSend)
        vm.sendState = .failed(.send(underlying: NSError(domain: "test", code: 1)))
        #expect(!vm.canRequestSend)
        vm.sendState = .idle
        #expect(vm.canRequestSend)
    }

    @Test func duplicateSendClickWhileSendingDoesNotEnqueueTwice() async throws {
        let queue = MockComposeSendQueue(statuses: [.sent])
        queue.executeDelay = .milliseconds(250)
        let vm = makeQueueViewModel(queue: queue)

        vm.requestSend()
        vm.confirmSendNow()
        try await waitUntil {
            queue.enqueueCallCount == 1
        }
        vm.requestSend()
        vm.requestSend()
        try await waitUntil(timeout: 3) {
            if case .sent = vm.sendState {
                return true
            }
            return false
        }

        #expect(queue.enqueueCallCount == 1)
        #expect(queue.executeCallCount == 1)
        if case .sent = vm.sendState {
            // OK
        } else {
            Issue.record("Expected sent, got \(vm.sendState)")
        }
    }

    @Test func manualRetryMovesFailedQueueItemBackToExecution() async throws {
        let queue = MockComposeSendQueue(statuses: [.failed, .sent])
        let vm = makeQueueViewModel(queue: queue)

        vm.requestSend()
        vm.confirmSendNow()
        try await waitUntil {
            if case .failed = vm.sendState {
                return true
            }
            return false
        }
        if case .failed = vm.sendState {
            // OK
        } else {
            Issue.record("Expected failed, got \(vm.sendState)")
        }

        vm.retrySend()
        try await waitUntil {
            if case .sent = vm.sendState {
                return true
            }
            return false
        }

        #expect(queue.retryCallCount == 1)
        #expect(queue.executeCallCount == 2)
        if case .sent = vm.sendState {
            // OK
        } else {
            Issue.record("Expected sent after retry, got \(vm.sendState)")
        }
    }

    @Test func needsConsentStateRequiresReauthorizationBeforeRetry() async throws {
        let queue = MockComposeSendQueue(statuses: [.needsConsent, .sent])
        let reauthorizeCounter = SendableCounter()
        let vm = makeQueueViewModel(queue: queue) { accountID in
            #expect(accountID == "acc1")
            reauthorizeCounter.increment()
        }

        vm.requestSend()
        vm.confirmSendNow()
        try await waitUntil {
            if case .needsReconsent = vm.sendState {
                return true
            }
            return false
        }
        if case .needsReconsent = vm.sendState {
            // OK
        } else {
            Issue.record("Expected needsReconsent, got \(vm.sendState)")
        }

        vm.reauthorizeAndRetry()
        try await waitUntil {
            if case .sent = vm.sendState {
                return true
            }
            return false
        }

        #expect(reauthorizeCounter.value == 1)
        #expect(queue.retryCallCount == 1)
        if case .sent = vm.sendState {
            // OK
        } else {
            Issue.record("Expected sent after reauthorization, got \(vm.sendState)")
        }
    }
}

private final class SendableCounter: @unchecked Sendable {
    private var count = 0

    var value: Int {
        count
    }

    func increment() {
        count += 1
    }
}

private final class MockComposeSendQueue: ComposeSendQueueProcessing, @unchecked Sendable {
    enum Status {
        case sent
        case failed
        case retrying
        case needsConsent
    }

    var executeDelay: Duration?
    private var statuses: [Status]
    private(set) var enqueueCallCount = 0
    private(set) var executeCallCount = 0
    private(set) var retryCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var lastDraft: DraftMessage?
    private var queuedItem: QueuedOutgoingMessage?

    init(statuses: [Status] = [.sent]) {
        self.statuses = statuses
    }

    func enqueueDraft(
        _ draft: DraftMessage,
        id: SendQueueItemID,
        idempotencyKey: SendIdempotencyKey
    ) async throws -> QueuedOutgoingMessage {
        enqueueCallCount += 1
        lastDraft = draft
        let item = queuedMessage(from: draft, id: id, idempotencyKey: idempotencyKey, status: .pending)
        queuedItem = item
        return item
    }

    func retry(id: SendQueueItemID) async throws -> QueuedOutgoingMessage? {
        retryCallCount += 1
        guard let queuedItem else { return nil }
        let retried = copy(queuedItem, status: .pending, failure: nil)
        self.queuedItem = retried
        return retried
    }

    func cancel(id: SendQueueItemID) async throws -> QueuedOutgoingMessage? {
        cancelCallCount += 1
        guard let queuedItem else { return nil }
        let canceled = copy(queuedItem, status: .canceled, failure: nil)
        self.queuedItem = canceled
        return canceled
    }

    func execute(id: SendQueueItemID) async throws -> SendQueueExecutionOutcome {
        executeCallCount += 1
        if let executeDelay {
            try? await Task.sleep(for: executeDelay)
        }
        let current = queuedItem ?? fallbackQueuedMessage(id: id)
        let status = statuses.isEmpty ? .sent : statuses.removeFirst()
        switch status {
        case .sent:
            let sent = copy(current, status: .sent, failure: nil)
            queuedItem = sent
            return .sent(sent)
        case .failed:
            let failed = copy(
                current,
                status: .failed,
                failure: SanitizedSendFailure(
                    category: .validation,
                    providerErrorCode: "validation_failed",
                    occurredAt: Date(timeIntervalSince1970: 2_000)
                )
            )
            queuedItem = failed
            return .failed(failed)
        case .retrying:
            let retrying = copy(
                current,
                status: .retryScheduled,
                failure: SanitizedSendFailure(
                    category: .rateLimited,
                    providerErrorCode: "429",
                    retryAfterSeconds: 60,
                    occurredAt: Date(timeIntervalSince1970: 2_000)
                )
            )
            queuedItem = retrying
            return .retryScheduled(retrying)
        case .needsConsent:
            let needsConsent = copy(
                current,
                status: .needsConsent,
                failure: SanitizedSendFailure(
                    category: .insufficientScope,
                    providerErrorCode: "insufficient_scope",
                    occurredAt: Date(timeIntervalSince1970: 2_000)
                )
            )
            queuedItem = needsConsent
            return .needsConsent(needsConsent)
        }
    }

    private func queuedMessage(
        from draft: DraftMessage,
        id: SendQueueItemID,
        idempotencyKey: SendIdempotencyKey,
        status: SendQueueStatus
    ) -> QueuedOutgoingMessage {
        QueuedOutgoingMessage(
            id: id,
            draftID: draft.id,
            provider: draft.provider,
            accountID: draft.accountID,
            idempotencyKey: idempotencyKey,
            status: status,
            from: draft.from,
            to: draft.to,
            cc: draft.cc,
            bcc: draft.bcc,
            subject: draft.subject,
            bodyText: draft.bodyText,
            bodyHTML: draft.bodyHTML,
            bodyStorage: draft.bodyStorage,
            threadID: draft.threadID,
            replyToProviderMessageID: draft.replyToProviderMessageID,
            rfcMessageID: draft.rfcMessageID,
            rfcInReplyTo: draft.rfcInReplyTo,
            rfcReferences: draft.rfcReferences,
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt
        )
    }

    private func fallbackQueuedMessage(id: SendQueueItemID) -> QueuedOutgoingMessage {
        QueuedOutgoingMessage(
            id: id,
            provider: .gmail,
            accountID: "acc1",
            idempotencyKey: "fallback-idempotency",
            status: .pending,
            from: Address(name: "Me", email: "me@example.com"),
            to: [Address(email: "recipient@example.com")],
            subject: "Fallback",
            bodyText: "Fallback",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func copy(
        _ item: QueuedOutgoingMessage,
        status: SendQueueStatus,
        failure: SanitizedSendFailure?
    ) -> QueuedOutgoingMessage {
        QueuedOutgoingMessage(
            id: item.id,
            draftID: item.draftID,
            provider: item.provider,
            accountID: item.accountID,
            idempotencyKey: item.idempotencyKey,
            status: status,
            from: item.from,
            to: item.to,
            cc: item.cc,
            bcc: item.bcc,
            subject: item.subject,
            bodyText: item.bodyText,
            bodyHTML: item.bodyHTML,
            bodyStorage: item.bodyStorage,
            threadID: item.threadID,
            replyToProviderMessageID: item.replyToProviderMessageID,
            providerMessageID: status == .sent ? "provider-message-1" : item.providerMessageID,
            providerThreadID: status == .sent ? "provider-thread-1" : item.providerThreadID,
            rfcMessageID: item.rfcMessageID,
            rfcInReplyTo: item.rfcInReplyTo,
            rfcReferences: item.rfcReferences,
            attempts: item.attempts + (status == .pending ? 0 : 1),
            retryPolicy: item.retryPolicy,
            nextAttemptAt: status == .retryScheduled ? Date(timeIntervalSince1970: 2_060) : nil,
            lastAttemptAt: Date(timeIntervalSince1970: 2_000),
            createdAt: item.createdAt,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            sentAt: status == .sent ? Date(timeIntervalSince1970: 2_000) : nil,
            sanitizedFailure: failure
        )
    }
}
