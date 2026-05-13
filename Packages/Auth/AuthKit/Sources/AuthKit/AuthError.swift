import Foundation

public enum AuthError: Error, Sendable {
    case cancelled
    case denied
    case network(any Error & Sendable)
    case decode(any Error & Sendable)
    case keychain(OSStatus)
    case invalidResponse
    case missingRefreshToken
}
