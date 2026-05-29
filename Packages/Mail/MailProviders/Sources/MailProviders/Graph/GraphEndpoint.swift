import Foundation

enum GraphEndpointName: String, Sendable, CustomStringConvertible {
    case listFolders
    case folderMessageDelta
    case getMessage
    case getAttachment
    case sendMail
    case markRead
    case moveMessage
    case archiveMessage
    case trashMessage
    case setFlag
    case updateCategories

    var description: String { rawValue }
}

enum GraphEndpoint {
    static let baseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    case listFolders
    case folderMessageDelta(folderId: String, deltaURL: URL?, pageSize: Int?)
    case getMessage(id: String)
    case getAttachment(messageId: String, attachmentId: String)
    case sendMail(GraphDTO.SendMailRequest)
    case markRead(messageId: String, isRead: Bool)
    case moveMessage(messageId: String, destinationFolderId: String)
    case archiveMessage(messageId: String)
    case trashMessage(messageId: String)
    case setFlag(messageId: String, isFlagged: Bool)
    case updateCategories(messageId: String, categories: [String])

    var name: GraphEndpointName {
        switch self {
        case .listFolders:
            return .listFolders
        case .folderMessageDelta:
            return .folderMessageDelta
        case .getMessage:
            return .getMessage
        case .getAttachment:
            return .getAttachment
        case .sendMail:
            return .sendMail
        case .markRead:
            return .markRead
        case .moveMessage:
            return .moveMessage
        case .archiveMessage:
            return .archiveMessage
        case .trashMessage:
            return .trashMessage
        case .setFlag:
            return .setFlag
        case .updateCategories:
            return .updateCategories
        }
    }

    var url: URL {
        switch self {
        case .folderMessageDelta(_, let deltaURL?, _):
            return deltaURL
        default:
            var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
            components.percentEncodedPath += path
            components.queryItems = queryItems
            return components.url!
        }
    }

    var httpMethod: String {
        switch self {
        case .listFolders, .folderMessageDelta, .getMessage, .getAttachment:
            return "GET"
        case .sendMail, .moveMessage, .archiveMessage, .trashMessage:
            return "POST"
        case .markRead, .setFlag, .updateCategories:
            return "PATCH"
        }
    }

    var httpBody: Data? {
        let encoder = JSONEncoder()
        switch self {
        case .sendMail(let request):
            return try? encoder.encode(request)
        case .markRead(_, let isRead):
            return try? encoder.encode(GraphMessagePatch(isRead: isRead))
        case .moveMessage(_, let destinationFolderId):
            return try? encoder.encode(GraphMoveRequest(destinationId: destinationFolderId))
        case .archiveMessage:
            return try? encoder.encode(GraphMoveRequest(destinationId: "archive"))
        case .trashMessage:
            return try? encoder.encode(GraphMoveRequest(destinationId: "deleteditems"))
        case .setFlag(_, let isFlagged):
            let status = isFlagged ? "flagged" : "notFlagged"
            return try? encoder.encode(GraphMessagePatch(flag: GraphDTO.FollowupFlag(flagStatus: status)))
        case .updateCategories(_, let categories):
            return try? encoder.encode(GraphMessagePatch(categories: categories))
        case .listFolders, .folderMessageDelta, .getMessage, .getAttachment:
            return nil
        }
    }

    private var path: String {
        switch self {
        case .listFolders:
            return "/me/mailFolders"
        case .folderMessageDelta(let folderId, nil, _):
            return "/me/mailFolders/\(Self.pathSegment(folderId))/messages/delta"
        case .folderMessageDelta(_, .some, _):
            return ""
        case .getMessage(let id):
            return "/me/messages/\(Self.pathSegment(id))"
        case .getAttachment(let messageId, let attachmentId):
            return "/me/messages/\(Self.pathSegment(messageId))/attachments/\(Self.pathSegment(attachmentId))"
        case .sendMail:
            return "/me/sendMail"
        case .markRead(let messageId, _):
            return "/me/messages/\(Self.pathSegment(messageId))"
        case .moveMessage(let messageId, _):
            return "/me/messages/\(Self.pathSegment(messageId))/move"
        case .archiveMessage(let messageId):
            return "/me/messages/\(Self.pathSegment(messageId))/move"
        case .trashMessage(let messageId):
            return "/me/messages/\(Self.pathSegment(messageId))/move"
        case .setFlag(let messageId, _):
            return "/me/messages/\(Self.pathSegment(messageId))"
        case .updateCategories(let messageId, _):
            return "/me/messages/\(Self.pathSegment(messageId))"
        }
    }

    private var queryItems: [URLQueryItem]? {
        switch self {
        case .folderMessageDelta(_, nil, let pageSize):
            guard let pageSize else { return nil }
            return [URLQueryItem(name: "$top", value: "\(pageSize)")]
        case .listFolders, .getMessage, .getAttachment, .sendMail, .markRead,
             .moveMessage, .archiveMessage, .trashMessage, .setFlag, .updateCategories,
             .folderMessageDelta(_, .some, _):
            return nil
        }
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=:")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct GraphMoveRequest: Encodable {
    let destinationId: String
}

private struct GraphMessagePatch: Encodable {
    let isRead: Bool?
    let flag: GraphDTO.FollowupFlag?
    let categories: [String]?

    init(isRead: Bool? = nil, flag: GraphDTO.FollowupFlag? = nil, categories: [String]? = nil) {
        self.isRead = isRead
        self.flag = flag
        self.categories = categories
    }
}
