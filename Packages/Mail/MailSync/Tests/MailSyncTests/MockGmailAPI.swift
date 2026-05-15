import Foundation
import MailProviders

final class MockGmailAPI: GmailAPI, @unchecked Sendable {
    var listMessagesResults: [Result<GmailDTO.MessageList, Error>] = []
    var getThreadResults: [String: Result<GmailDTO.Thread, Error>] = [:]
    var listHistoryResults: [Result<GmailDTO.HistoryResponse, Error>] = []
    var getMessageResults: [String: Result<GmailDTO.Message, Error>] = [:]

    private var listMessagesCallIndex = 0
    private var listHistoryCallIndex = 0

    var listMessagesCalled = 0
    var getThreadCalled = 0
    var getThreadCalledIds: [String] = []

    func listMessages(query: String?, pageToken: String?, maxResults: Int) async throws -> GmailDTO.MessageList {
        listMessagesCalled += 1
        guard listMessagesCallIndex < listMessagesResults.count else {
            return GmailDTO.MessageList(messages: nil, nextPageToken: nil)
        }
        let result = listMessagesResults[listMessagesCallIndex]
        listMessagesCallIndex += 1
        return try result.get()
    }

    func getMessage(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Message {
        guard let result = getMessageResults[id] else {
            throw GmailAPIError.invalidResponse
        }
        return try result.get()
    }

    func getThread(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Thread {
        getThreadCalled += 1
        getThreadCalledIds.append(id)
        guard let result = getThreadResults[id] else {
            throw GmailAPIError.invalidResponse
        }
        return try result.get()
    }

    func listHistory(startHistoryId: String, pageToken: String?) async throws -> GmailDTO.HistoryResponse {
        guard listHistoryCallIndex < listHistoryResults.count else {
            return GmailDTO.HistoryResponse(history: nil, nextPageToken: nil, historyId: startHistoryId)
        }
        let result = listHistoryResults[listHistoryCallIndex]
        listHistoryCallIndex += 1
        return try result.get()
    }

    func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage {
        throw GmailAPIError.invalidResponse
    }
}
