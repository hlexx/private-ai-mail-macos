import Foundation
import MailDomain

public protocol GraphAPI: Sendable {
    func listFolders() async throws -> GraphDTO.MailFolderList
    func folderMessageDelta(folderId: String, deltaURL: URL?, pageSize: Int?) async throws -> GraphDTO.MessageDeltaResponse
    func getMessage(id: String) async throws -> GraphDTO.Message
    func getAttachment(messageId: String, attachmentId: String) async throws -> GraphDTO.AttachmentContent
    func sendMail(_ request: GraphDTO.SendMailRequest) async throws -> GraphDTO.SendResult
    func markRead(messageId: String, isRead: Bool) async throws -> GraphDTO.Message
    func moveMessage(messageId: String, destinationFolderId: String) async throws -> GraphDTO.Message
    func archiveMessage(messageId: String) async throws -> GraphDTO.Message
    func trashMessage(messageId: String) async throws -> GraphDTO.Message
    func setFlag(messageId: String, isFlagged: Bool) async throws -> GraphDTO.Message
    func updateCategories(messageId: String, categories: [String]) async throws -> GraphDTO.Message
}

public extension GraphAPI {
    func getAttachmentData(messageId: String, attachmentId: String) async throws -> Data {
        let content = try await getAttachment(messageId: messageId, attachmentId: attachmentId)
        guard let encoded = content.contentBytes,
              let data = Data(base64Encoded: encoded) else {
            throw GraphAPIError.decodingError("Attachment response did not include decodable contentBytes.")
        }
        return data
    }

    func archiveMessage(messageId: String) async throws -> GraphDTO.Message {
        guard let archiveFolder = GraphMailboxMapper.graphWellKnownFolder(for: .archive) else {
            throw GraphAPIError.invalidResponse
        }
        return try await moveMessage(messageId: messageId, destinationFolderId: archiveFolder)
    }

    func trashMessage(messageId: String) async throws -> GraphDTO.Message {
        guard let trashFolder = GraphMailboxMapper.graphWellKnownFolder(for: .trash) else {
            throw GraphAPIError.invalidResponse
        }
        return try await moveMessage(messageId: messageId, destinationFolderId: trashFolder)
    }
}
