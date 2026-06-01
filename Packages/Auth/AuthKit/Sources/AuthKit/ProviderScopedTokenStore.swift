import Foundation

public struct TokenCredentialScope: Codable, Equatable, Hashable, Sendable {
    public let provider: AuthProvider
    public let accountID: String

    public init(provider: AuthProvider, accountID: String) throws {
        self.provider = provider
        self.accountID = try AuthValueValidator.nonEmpty(accountID, field: "accountID")
    }

    public var storageAccountID: String {
        "\(provider.rawValue):\(accountID)"
    }
}

public struct ProviderScopedTokenStore: Sendable {
    private let base: any TokenStore

    public init(base: any TokenStore) {
        self.base = base
    }

    public func save(_ credential: TokenCredential, for scope: TokenCredentialScope) throws {
        try base.save(credential, for: scope.storageAccountID)
    }

    public func load(for scope: TokenCredentialScope) throws -> TokenCredential? {
        try base.load(for: scope.storageAccountID)
    }

    public func requireCredential(for scope: TokenCredentialScope) throws -> TokenCredential {
        guard let credential = try load(for: scope) else {
            throw AuthError.missingProviderCredential(
                provider: scope.provider,
                accountID: scope.accountID
            )
        }
        return credential
    }

    public func delete(for scope: TokenCredentialScope) throws {
        try base.delete(for: scope.storageAccountID)
    }
}
