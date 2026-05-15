import Foundation
import MailDomain
@testable import ComposeFeature

final class MockComposeService: ComposeService, @unchecked Sendable {
    var sendResult: Result<SentEcho, Error> = .success(
        SentEcho(messageID: "mock_msg_1", threadID: "mock_thread_1", sentAt: Date())
    )
    private(set) var sendCallCount = 0
    private(set) var lastDraft: ComposeDraft?

    func send(_ draft: ComposeDraft) async throws -> SentEcho {
        sendCallCount += 1
        lastDraft = draft
        return try sendResult.get()
    }
}
