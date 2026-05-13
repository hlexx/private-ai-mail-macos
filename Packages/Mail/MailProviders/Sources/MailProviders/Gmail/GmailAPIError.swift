import Foundation

public enum GmailAPIError: Error, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case networkError(any Error & Sendable)
    case decodingError(any Error & Sendable)
    case exhaustedRetries
    case invalidResponse
}
