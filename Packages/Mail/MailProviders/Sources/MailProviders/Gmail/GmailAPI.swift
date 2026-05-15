import Foundation
import MailDomain

public protocol GmailAPI: Sendable {
    func listMessages(query: String?, pageToken: String?, maxResults: Int) async throws -> GmailDTO.MessageList
    func getMessage(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Message
    func getThread(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Thread
    func listHistory(startHistoryId: String, pageToken: String?) async throws -> GmailDTO.HistoryResponse
    func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage
}

public enum GmailMessageFormat: String, Sendable {
    case full
    case metadata
    case minimal
    case raw
}
