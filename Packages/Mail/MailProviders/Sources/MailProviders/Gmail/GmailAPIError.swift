import Foundation

public enum GmailAPIError: Error, Sendable {
    case missingAttachmentIdentifier
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case networkError(any Error & Sendable)
    case decodingError(any Error & Sendable)
    case insufficientScope
    case exhaustedRetries
    case invalidResponse
}

extension GmailAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAttachmentIdentifier:
            return "Gmail attachment is missing a download identifier. Re-sync the message before trying again."
        case .unauthorized:
            return "Gmail authentication failed (401). The access token was rejected — try removing the account and reconnecting."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Gmail API rate limit hit (429). Retry after \(Int(retryAfter))s."
            }
            return "Gmail API rate limit hit (429)."
        case .serverError(let code):
            switch code {
            case 404:
                return "Gmail attachment or message was not found. Re-sync the mailbox and try again."
            case 500 ... 599:
                return "Gmail is temporarily unavailable (HTTP \(code)). Try again shortly."
            default:
                return "Gmail API request failed (HTTP \(code))."
            }
        case .networkError(let inner):
            return "Network error reaching Gmail: \((inner as? LocalizedError)?.errorDescription ?? String(describing: inner))"
        case .decodingError(let inner):
            return "Failed to decode Gmail response: \((inner as? LocalizedError)?.errorDescription ?? String(describing: inner))"
        case .insufficientScope:
            return "Gmail rejected the request as out of scope (403). The OAuth token doesn't grant message-body access — remove the account and reconnect to refresh scopes."
        case .exhaustedRetries:
            return "Gave up after repeated Gmail API retries."
        case .invalidResponse:
            return "Gmail returned a malformed response."
        }
    }
}
