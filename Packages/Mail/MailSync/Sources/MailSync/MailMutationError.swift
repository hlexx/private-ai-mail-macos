import AuthKit
import Foundation
import MailProviders

public enum MailMutationOperation: String, Sendable {
    case archive
    case unarchive
    case star
    case unstar
    case markRead
    case markUnread
    case trash
    case untrash

    var userLabel: String {
        switch self {
        case .archive: return "Archive"
        case .unarchive: return "Unarchive"
        case .star: return "Star"
        case .unstar: return "Unstar"
        case .markRead: return "Mark read"
        case .markUnread: return "Mark unread"
        case .trash: return "Move to trash"
        case .untrash: return "Restore from trash"
        }
    }
}

public struct MailMutationError: Error, Sendable, Equatable {
    public let operation: MailMutationOperation
    public let category: MailProviderErrorCategory

    public init(operation: MailMutationOperation, category: MailProviderErrorCategory) {
        self.operation = operation
        self.category = category
    }
}

extension MailMutationError: LocalizedError {
    public var errorDescription: String? {
        switch category {
        case .missingCredential:
            return "\(operation.userLabel) failed. Reconnect Gmail to continue."
        case .insufficientScope:
            return "\(operation.userLabel) failed. Gmail needs re-authorization for this permission."
        case .authExpired:
            return "\(operation.userLabel) failed. Your Gmail session expired; reconnect the account."
        case .rateLimited:
            return "\(operation.userLabel) failed. Gmail rate-limited this account; try again shortly."
        case .offline:
            return "\(operation.userLabel) failed. You appear to be offline."
        case .providerUnavailable:
            return "\(operation.userLabel) failed. Gmail rejected the request; try again."
        case .notFound:
            return "\(operation.userLabel) failed. Gmail no longer has this thread."
        case .invalidResponse:
            return "\(operation.userLabel) failed. Gmail returned an unreadable response."
        case .unsupportedOperation:
            return "\(operation.userLabel) is not supported for this Gmail account."
        case .conflict:
            return "\(operation.userLabel) failed because Gmail reported a conflicting update."
        }
    }
}

extension MailMutationError {
    static func wrap(operation: MailMutationOperation, error: any Error) -> MailMutationError {
        if let error = error as? MailMutationError {
            return error
        }
        if let error = error as? GmailAPIError {
            return MailMutationError(operation: operation, category: error.sharedCategory)
        }
        if let error = error as? AuthError {
            return MailMutationError(operation: operation, category: error.mailProviderCategory)
        }
        if let error = error as? URLError {
            return MailMutationError(operation: operation, category: error.mailProviderCategory)
        }
        return MailMutationError(operation: operation, category: .providerUnavailable)
    }
}

private extension AuthError {
    var mailProviderCategory: MailProviderErrorCategory {
        switch self {
        case .missingCredential, .missingProviderCredential:
            return .missingCredential
        case .denied, .missingRefreshToken:
            return .authExpired
        case .network:
            return .offline
        case .decode, .invalidResponse:
            return .invalidResponse
        case .keychain, .cancelled, .invalidConfiguration:
            return .providerUnavailable
        }
    }
}

private extension URLError {
    var mailProviderCategory: MailProviderErrorCategory {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        default:
            return .providerUnavailable
        }
    }
}
