import Foundation
import MailDomain

public protocol GmailAPI: Sendable {
    func listMessages(query: String?, pageToken: String?, maxResults: Int) async throws -> GmailDTO.MessageList
    func getMessage(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Message
    func getThread(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Thread
    func getAttachmentData(messageId: String, attachmentId: String) async throws -> Data
    func listHistory(startHistoryId: String, pageToken: String?) async throws -> GmailDTO.HistoryResponse
    func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage
    func createDraft(raw base64URL: String, threadId: String?) async throws -> GmailDTO.Draft
    func listLabels() async throws -> [GmailDTO.Label]
    func modifyThread(id: String, addLabelIds: [String], removeLabelIds: [String]) async throws -> GmailDTO.Thread
}

public extension GmailAPI {
    func getAttachmentData(messageId _: String, attachmentId _: String) async throws -> Data {
        throw GmailAPIError.invalidResponse
    }

    func createDraft(raw _: String, threadId _: String?) async throws -> GmailDTO.Draft {
        throw GmailAPIError.invalidResponse
    }
}

public enum GmailMessageFormat: String, Sendable {
    case full
    case metadata
    case minimal
    case raw
}
