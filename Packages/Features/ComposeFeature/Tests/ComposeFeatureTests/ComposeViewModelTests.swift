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
}
