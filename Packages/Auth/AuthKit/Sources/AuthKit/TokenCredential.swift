import Foundation

public struct TokenCredential: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let tokenType: String

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        tokenType: String = "Bearer"
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}
