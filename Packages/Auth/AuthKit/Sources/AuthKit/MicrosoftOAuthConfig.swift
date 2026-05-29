import Foundation

public struct MicrosoftOAuthConfig: Sendable, Equatable {
    public let clientID: String
    public let tenant: String
    public let redirectURI: String
    public let scopes: [String]

    public static let defaultTenant = "common"

    public static let defaultScopes = [
        "openid",
        "profile",
        "email",
        "offline_access",
        "Mail.ReadWrite",
        "Mail.Send",
    ]

    public init(
        clientID: String,
        tenant: String = Self.defaultTenant,
        redirectURI: String,
        scopes: [String] = Self.defaultScopes
    ) throws {
        self.clientID = try AuthValueValidator.nonEmpty(clientID, field: "clientID")
        self.tenant = try AuthValueValidator.nonEmpty(tenant, field: "tenant")
        self.redirectURI = try AuthValueValidator.nonEmpty(redirectURI, field: "redirectURI")
        self.scopes = try Self.validateScopes(scopes)
    }

    public var authorizationEndpoint: URL {
        microsoftIdentityEndpoint(path: "authorize")
    }

    public var tokenEndpoint: URL {
        microsoftIdentityEndpoint(path: "token")
    }

    public func missingScopes(from grantedScopes: [String]) -> [String] {
        let granted = Set(grantedScopes.map(Self.normalizedScope))
        return scopes.filter { !granted.contains(Self.normalizedScope($0)) }
    }

    public func reconsentSignal(
        accountID: String,
        grantedScopes: [String]
    ) throws -> OAuthReconsentSignal {
        try OAuthReconsentSignal(
            provider: .outlook,
            accountID: accountID,
            missingScopes: missingScopes(from: grantedScopes)
        )
    }

    private func microsoftIdentityEndpoint(path: String) -> URL {
        URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/\(path)")!
    }

    private static func validateScopes(_ scopes: [String]) throws -> [String] {
        let normalized = scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !normalized.isEmpty, normalized.allSatisfy({ !$0.isEmpty }) else {
            throw AuthError.invalidConfiguration(field: "scopes")
        }
        var deduped: [String] = []
        var seen: Set<String> = []
        for scope in normalized where !seen.contains(scope) {
            deduped.append(scope)
            seen.insert(scope)
        }
        return deduped
    }

    private static func normalizedScope(_ scope: String) -> String {
        scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct OAuthReconsentSignal: Equatable, Sendable {
    public let provider: AuthProvider
    public let accountID: String
    public let missingScopes: [String]

    public init(
        provider: AuthProvider,
        accountID: String,
        missingScopes: [String]
    ) throws {
        self.provider = provider
        self.accountID = try AuthValueValidator.nonEmpty(accountID, field: "accountID")
        self.missingScopes = missingScopes
    }

    public var requiresReconsent: Bool {
        !missingScopes.isEmpty
    }
}
