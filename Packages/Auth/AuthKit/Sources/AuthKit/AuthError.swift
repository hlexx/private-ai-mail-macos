import Foundation

public enum AuthError: Error, Sendable {
    case cancelled
    case denied
    case network(any Error & Sendable)
    case decode(any Error & Sendable)
    case keychain(OSStatus)
    case invalidResponse
    case missingRefreshToken
    case missingCredential(accountID: String)
    case missingProviderCredential(provider: AuthProvider, accountID: String)
    case invalidConfiguration(field: String)
}

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Authorization was cancelled."
        case .denied:
            return "Authorization was denied."
        case .network(let error):
            return "Authorization network error: \(describe(error))"
        case .decode(let error):
            return "Failed to decode authorization response: \(describe(error))"
        case .keychain(let status):
            return "Keychain operation failed with status \(status)."
        case .invalidResponse:
            return "Authorization server returned an invalid response."
        case .missingRefreshToken:
            return "Authorization response did not include a refresh token."
        case .missingCredential(let accountID):
            return "No saved credential for account \(accountID). Reconnect the account."
        case .missingProviderCredential(let provider, let accountID):
            return "No saved \(provider.rawValue) credential for account \(accountID). Reconnect the account."
        case .invalidConfiguration(let field):
            return "Authorization configuration is missing \(field)."
        }
    }

    private func describe(_ error: any Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }
}
