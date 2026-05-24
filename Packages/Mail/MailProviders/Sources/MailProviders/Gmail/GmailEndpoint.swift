import Foundation

enum GmailEndpoint {
    static let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"

    case listMessages(query: String?, pageToken: String?, maxResults: Int)
    case getMessage(id: String, format: GmailMessageFormat)
    case getThread(id: String, format: GmailMessageFormat)
    case getAttachment(messageId: String, attachmentId: String)
    case listHistory(startHistoryId: String, pageToken: String?)
    case sendMessage(raw: String, threadId: String?)
    case listLabels
    case modifyThread(id: String, addLabelIds: [String], removeLabelIds: [String])

    var url: URL {
        var components = URLComponents(string: Self.baseURL + path)!
        components.queryItems = queryItems
        return components.url!
    }

    private var path: String {
        switch self {
        case .listMessages:
            return "/messages"
        case .getMessage(let id, _):
            return "/messages/\(id)"
        case .getThread(let id, _):
            return "/threads/\(id)"
        case .getAttachment(let messageId, let attachmentId):
            return "/messages/\(messageId)/attachments/\(attachmentId)"
        case .listHistory:
            return "/history"
        case .sendMessage:
            return "/messages/send"
        case .listLabels:
            return "/labels"
        case .modifyThread(let id, _, _):
            return "/threads/\(id)/modify"
        }
    }

    /// Gmail API quota cost per method (units per request).
    var quotaCost: Int {
        switch self {
        case .listMessages: return 5
        case .getMessage: return 5
        case .getThread: return 10
        case .getAttachment: return 5
        case .listHistory: return 2
        case .sendMessage: return 100
        case .listLabels: return 1
        case .modifyThread: return 5
        }
    }

    var httpMethod: String {
        switch self {
        case .sendMessage: return "POST"
        case .modifyThread: return "POST"
        case .listLabels: return "GET"
        default: return "GET"
        }
    }

    var httpBody: Data? {
        switch self {
        case .sendMessage(let raw, let threadId):
            var dict: [String: String] = ["raw": raw]
            if let threadId { dict["threadId"] = threadId }
            return try? JSONSerialization.data(withJSONObject: dict)
        case .modifyThread(_, let addLabelIds, let removeLabelIds):
            var dict: [String: [String]] = [:]
            if !addLabelIds.isEmpty { dict["addLabelIds"] = addLabelIds }
            if !removeLabelIds.isEmpty { dict["removeLabelIds"] = removeLabelIds }
            return try? JSONSerialization.data(withJSONObject: dict)
        case .listLabels:
            return nil
        default:
            return nil
        }
    }

    private var queryItems: [URLQueryItem] {
        switch self {
        case .listMessages(let query, let pageToken, let maxResults):
            var items = [URLQueryItem(name: "maxResults", value: "\(maxResults)")]
            if let query { items.append(URLQueryItem(name: "q", value: query)) }
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            return items
        case .getMessage(_, let format):
            return [URLQueryItem(name: "format", value: format.rawValue)]
        case .getThread(_, let format):
            return [URLQueryItem(name: "format", value: format.rawValue)]
        case .getAttachment:
            return []
        case .listHistory(let startHistoryId, let pageToken):
            var items = [URLQueryItem(name: "startHistoryId", value: startHistoryId)]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            return items
        case .sendMessage:
            return []
        case .listLabels:
            return []
        case .modifyThread:
            return []
        }
    }
}
