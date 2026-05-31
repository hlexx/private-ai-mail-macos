import AppFoundation
import AuthKit
import Foundation
import MailProviders

public enum SyncEvent: Sendable {
    case progress(Double)
    case threadUpserted(String)
    case error(SyncError)
    case state(SyncState)
}

public enum SyncError: Error, Sendable {
    case bootstrapFailed(any Error & Sendable)
    case incrementalFailed(any Error & Sendable)
    case rateLimited(retryAfter: TimeInterval)
    case historyExpired
}

extension SyncError: LocalizedError {
    public var errorDescription: String? {
        userActionableFailure.message
    }
}

public extension SyncError {
    var userActionableFailure: UserActionableFailure {
        switch self {
        case .bootstrapFailed(let inner):
            return Self.userActionableFailure(for: inner)
        case .incrementalFailed(let inner):
            return Self.userActionableFailure(for: inner)
        case .rateLimited(let retryAfter):
            return UserActionableFailure(
                category: .rateLimit,
                operation: .sync,
                provider: "Gmail",
                retryAfterSeconds: Int(retryAfter)
            )
        case .historyExpired:
            return UserActionableFailure(category: .providerUnavailable, operation: .sync, provider: "Gmail")
        }
    }

    private static func userActionableFailure(for error: any Error) -> UserActionableFailure {
        if let failure = error as? UserActionableFailure {
            return failure
        }
        if let gmailError = error as? GmailAPIError {
            return gmailError.userActionableFailure(operation: .sync)
        }
        if let graphError = error as? GraphAPIError {
            return graphError.userActionableFailure(operation: .sync)
        }
        if let authError = error as? AuthError {
            return authError.userActionableFailure(operation: .sync, provider: "Gmail")
        }
        return UserActionableFailure.coerce(error, operation: .sync, provider: "Gmail")
    }
}
