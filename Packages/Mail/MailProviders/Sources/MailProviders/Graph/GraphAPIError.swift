import Foundation

public enum GraphAPIError: Error, Sendable, Equatable {
    case missingAttachmentIdentifier
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, code: String?)
    case networkError(String)
    case decodingError(String)
    case insufficientScope
    case invalidResponse
}

extension GraphAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAttachmentIdentifier:
            return "Microsoft Graph attachment is missing a download identifier. Re-sync the Outlook message before trying again."
        case .unauthorized:
            return "Microsoft Graph authentication failed (401). Reconnect the Outlook account."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Microsoft Graph rate limit hit (429). Retry after \(Int(retryAfter))s."
            }
            return "Microsoft Graph rate limit hit (429)."
        case .serverError(let statusCode, let code):
            if statusCode == 404 {
                return "Microsoft Graph attachment or message was not found. Re-sync the Outlook mailbox and try again."
            }
            if let code {
                return "Microsoft Graph error \(code) (HTTP \(statusCode))."
            }
            return "Microsoft Graph server error (HTTP \(statusCode))."
        case .networkError(let description):
            return "Network error reaching Microsoft Graph: \(description)"
        case .decodingError(let description):
            return "Failed to decode Microsoft Graph response: \(description)"
        case .insufficientScope:
            return "Microsoft Graph rejected the request as out of scope. Reconnect the Outlook account to refresh consent."
        case .invalidResponse:
            return "Microsoft Graph returned a malformed response."
        }
    }
}

public extension GraphAPIError {
    var sharedCategory: MailProviderErrorCategory {
        switch self {
        case .missingAttachmentIdentifier:
            return .invalidResponse
        case .unauthorized:
            return .authExpired
        case .rateLimited:
            return .rateLimited
        case .serverError(let statusCode, _):
            return Self.mapServerStatus(statusCode)
        case .networkError:
            return .offline
        case .decodingError, .invalidResponse:
            return .invalidResponse
        case .insufficientScope:
            return .insufficientScope
        }
    }

    private static func mapServerStatus(_ statusCode: Int) -> MailProviderErrorCategory {
        switch statusCode {
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 429:
            return .rateLimited
        case 501:
            return .unsupportedOperation
        case 500 ... 599:
            return .providerUnavailable
        default:
            return .providerUnavailable
        }
    }
}
