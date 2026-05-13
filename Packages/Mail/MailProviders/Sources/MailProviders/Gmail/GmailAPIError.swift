import Foundation

public enum GmailAPIError: Error, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case networkError(any Error)
    case decodingError(any Error)
    case exhaustedRetries
    case invalidResponse
}
