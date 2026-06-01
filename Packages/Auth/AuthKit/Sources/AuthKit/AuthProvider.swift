import Foundation

public struct AuthProvider: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public static let gmail = AuthProvider(rawValue: "gmail")

    /// Microsoft Graph-backed Outlook provider persisted as `outlook`.
    public static let outlook = AuthProvider(rawValue: "outlook")

    public static let microsoftGraph = AuthProvider.outlook
}

public struct AuthAccountIdentity: Codable, Equatable, Sendable {
    public let accountID: String
    public let provider: AuthProvider
    public let email: String
    public let displayName: String?
    public let providerUserID: String?

    public init(
        accountID: String,
        provider: AuthProvider,
        email: String,
        displayName: String? = nil,
        providerUserID: String? = nil
    ) throws {
        self.accountID = try AuthValueValidator.nonEmpty(accountID, field: "accountID")
        self.provider = provider
        self.email = try AuthValueValidator.nonEmpty(email, field: "email")
        self.displayName = displayName
        self.providerUserID = providerUserID
    }

    public var credentialScope: TokenCredentialScope {
        get throws {
            try TokenCredentialScope(provider: provider, accountID: accountID)
        }
    }
}

enum AuthValueValidator {
    static func nonEmpty(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.invalidConfiguration(field: field)
        }
        return trimmed
    }
}
