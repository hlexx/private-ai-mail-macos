import Foundation

public enum AuthError: Error, Sendable {
    case cancelled
    case denied
    case network(any Error)
    case decode(any Error)
    case keychain(OSStatus)
    case invalidResponse
    case missingRefreshToken
}
