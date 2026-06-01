import Foundation
@testable import MailProviders

enum ProviderFixtureError: Error {
    case missingFixture(String)
    case missingFixtureRoot
    case invalidBase64URL(String)
}

enum ProviderFixtureLoader {
    static func decode<Value: Decodable>(_ type: Value.Type, _ path: String) throws -> Value {
        let url = try fixtureURL(path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    static func allFixtureFiles() throws -> [URL] {
        guard let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw ProviderFixtureError.missingFixtureRoot
        }
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let files = enumerator?.compactMap { $0 as? URL }.filter { !$0.hasDirectoryPath } ?? []
        return files.sorted { $0.path < $1.path }
    }

    static func base64URLDecode(_ encoded: String) throws -> Data {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else {
            throw ProviderFixtureError.invalidBase64URL(encoded)
        }
        return data
    }

    private static func fixtureURL(_ path: String) throws -> URL {
        let components = path.split(separator: "/").map(String.init)
        guard let fileName = components.last else {
            throw ProviderFixtureError.missingFixture(path)
        }
        let fileComponents = fileName.split(separator: ".", maxSplits: 1).map(String.init)
        let resourceName = fileComponents[0]
        let fileExtension = fileComponents.count > 1 ? fileComponents[1] : nil
        let subdirectory = (["Fixtures"] + components.dropLast()).joined(separator: "/")

        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) else {
            throw ProviderFixtureError.missingFixture(path)
        }
        return url
    }
}

final class FixtureGmailSendAPI: GmailAPI, @unchecked Sendable {
    private let sentMessage: GmailDTO.SentMessage
    private(set) var lastRaw: String?
    private(set) var lastThreadID: String?

    init(sentMessage: GmailDTO.SentMessage) {
        self.sentMessage = sentMessage
    }

    func listMessages(query _: String?, pageToken _: String?, maxResults _: Int) async throws -> GmailDTO.MessageList {
        throw GmailAPIError.invalidResponse
    }

    func getMessage(id _: String, format _: GmailMessageFormat) async throws -> GmailDTO.Message {
        throw GmailAPIError.invalidResponse
    }

    func getThread(id _: String, format _: GmailMessageFormat) async throws -> GmailDTO.Thread {
        throw GmailAPIError.invalidResponse
    }

    func listHistory(startHistoryId: String, pageToken _: String?) async throws -> GmailDTO.HistoryResponse {
        GmailDTO.HistoryResponse(historyId: startHistoryId)
    }

    func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage {
        lastRaw = base64URL
        lastThreadID = threadId
        return sentMessage
    }

    func listLabels() async throws -> [GmailDTO.Label] {
        []
    }

    func modifyThread(id _: String, addLabelIds _: [String], removeLabelIds _: [String]) async throws -> GmailDTO.Thread {
        throw GmailAPIError.invalidResponse
    }
}

final class FixtureGraphSendAPI: GraphAPI, @unchecked Sendable {
    private let result: GraphDTO.SendResult
    private(set) var lastRequest: GraphDTO.SendMailRequest?

    init(result: GraphDTO.SendResult) {
        self.result = result
    }

    func listFolders() async throws -> GraphDTO.MailFolderList {
        throw GraphAPIError.invalidResponse
    }

    func folderMessageDelta(folderId _: String, deltaURL _: URL?, pageSize _: Int?) async throws -> GraphDTO.MessageDeltaResponse {
        throw GraphAPIError.invalidResponse
    }

    func getMessage(id _: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func getAttachment(messageId _: String, attachmentId _: String) async throws -> GraphDTO.AttachmentContent {
        throw GraphAPIError.invalidResponse
    }

    func sendMail(_ request: GraphDTO.SendMailRequest) async throws -> GraphDTO.SendResult {
        lastRequest = request
        return result
    }

    func markRead(messageId _: String, isRead _: Bool) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func moveMessage(messageId _: String, destinationFolderId _: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func archiveMessage(messageId _: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func trashMessage(messageId _: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func setFlag(messageId _: String, isFlagged _: Bool) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func updateCategories(messageId _: String, categories _: [String]) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }
}
