import Foundation
import MailProviders

final class MockGmailAPI: GmailAPI, @unchecked Sendable {
    var sendMessageResult: Result<GmailDTO.SentMessage, Error> = .success(
        GmailDTO.SentMessage(id: "sent_123", threadId: "thread_456", labelIds: ["SENT"])
    )
    private(set) var sendCallCount = 0
    private(set) var lastRaw: String?
    private(set) var lastThreadId: String?

    func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage {
        sendCallCount += 1
        lastRaw = base64URL
        lastThreadId = threadId
        return try sendMessageResult.get()
    }

    func listMessages(query: String?, pageToken: String?, maxResults: Int) async throws -> GmailDTO.MessageList {
        GmailDTO.MessageList(messages: nil, nextPageToken: nil)
    }

    func getMessage(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Message {
        throw GmailAPIError.invalidResponse
    }

    func getThread(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Thread {
        throw GmailAPIError.invalidResponse
    }

    func listHistory(startHistoryId: String, pageToken: String?) async throws -> GmailDTO.HistoryResponse {
        GmailDTO.HistoryResponse(history: nil, nextPageToken: nil, historyId: startHistoryId)
    }
}
