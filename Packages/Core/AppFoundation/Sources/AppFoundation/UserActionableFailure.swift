import Foundation

public enum UserActionableFailureCategory: String, Codable, CaseIterable, Sendable {
    case offline
    case missingCredential
    case insufficientScope
    case rateLimit
    case providerUnavailable
    case unsupportedOperation
    case unknown

    public var title: String {
        switch self {
        case .offline:
            return String(localized: "failure.category.offline.title", defaultValue: "Offline")
        case .missingCredential:
            return String(localized: "failure.category.missingCredential.title", defaultValue: "Reconnect account")
        case .insufficientScope:
            return String(localized: "failure.category.insufficientScope.title", defaultValue: "Permission needed")
        case .rateLimit:
            return String(localized: "failure.category.rateLimit.title", defaultValue: "Rate limited")
        case .providerUnavailable:
            return String(localized: "failure.category.providerUnavailable.title", defaultValue: "Provider unavailable")
        case .unsupportedOperation:
            return String(localized: "failure.category.unsupportedOperation.title", defaultValue: "Unsupported operation")
        case .unknown:
            return String(localized: "failure.category.unknown.title", defaultValue: "Unknown failure")
        }
    }
}

public enum UserActionableFailureOperation: String, Codable, CaseIterable, Sendable {
    case account
    case attachment
    case search
    case send
    case sync

    var displayName: String {
        switch self {
        case .account:
            return String(localized: "failure.operation.account", defaultValue: "Account")
        case .attachment:
            return String(localized: "failure.operation.attachment", defaultValue: "Attachment")
        case .search:
            return String(localized: "failure.operation.search", defaultValue: "Search")
        case .send:
            return String(localized: "failure.operation.send", defaultValue: "Send")
        case .sync:
            return String(localized: "failure.operation.sync", defaultValue: "Sync")
        }
    }

    var actionDescription: String {
        switch self {
        case .account:
            return String(localized: "failure.operation.account.action", defaultValue: "use this account")
        case .attachment:
            return String(localized: "failure.operation.attachment.action", defaultValue: "download this attachment")
        case .search:
            return String(localized: "failure.operation.search.action", defaultValue: "search mail")
        case .send:
            return String(localized: "failure.operation.send.action", defaultValue: "send this message")
        case .sync:
            return String(localized: "failure.operation.sync.action", defaultValue: "sync mail")
        }
    }
}

public struct UserActionableFailure: Error, Equatable, Sendable {
    public let category: UserActionableFailureCategory
    public let operation: UserActionableFailureOperation
    public let provider: String?
    public let retryAfterSeconds: Int?

    public init(
        category: UserActionableFailureCategory,
        operation: UserActionableFailureOperation,
        provider: String? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.category = category
        self.operation = operation
        self.provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.retryAfterSeconds = retryAfterSeconds
    }

    public var title: String {
        category.title
    }

    public var message: String {
        let providerName = provider ?? String(localized: "failure.provider.default", defaultValue: "this provider")
        switch category {
        case .offline:
            return String(
                localized: "failure.message.offline",
                defaultValue: "\(operation.displayName) cannot reach \(providerName) while offline. Check your connection and try again."
            )
        case .missingCredential:
            return String(
                localized: "failure.message.missingCredential",
                defaultValue: "Reconnect \(providerName) to \(operation.actionDescription)."
            )
        case .insufficientScope:
            return String(
                localized: "failure.message.insufficientScope",
                defaultValue: "Re-authorize \(providerName) so Re:Box has permission to \(operation.actionDescription)."
            )
        case .rateLimit:
            if let retryAfterSeconds {
                return String(
                    localized: "failure.message.rateLimit.retryAfter",
                    defaultValue: "\(providerName) is rate-limiting \(operation.displayName.lowercased()). Re:Box will retry in \(retryAfterSeconds)s."
                )
            }
            return String(
                localized: "failure.message.rateLimit",
                defaultValue: "\(providerName) is rate-limiting \(operation.displayName.lowercased()). Re:Box will retry automatically."
            )
        case .providerUnavailable:
            if operation == .attachment, provider == nil {
                return String(
                    localized: "failure.message.attachment.providerUnavailable",
                    defaultValue: "Attachment data is unavailable right now. Try again later."
                )
            }
            return String(
                localized: "failure.message.providerUnavailable",
                defaultValue: "\(providerName) is unavailable right now. Try again later."
            )
        case .unsupportedOperation:
            if operation == .attachment {
                return String(
                    localized: "failure.message.attachment.unsupportedOperation",
                    defaultValue: "This attachment is not supported in this build."
                )
            }
            return String(
                localized: "failure.message.unsupportedOperation",
                defaultValue: "\(operation.displayName) is not supported for \(providerName) in this build."
            )
        case .unknown:
            if operation == .attachment {
                return String(
                    localized: "failure.message.attachment.unknown",
                    defaultValue: "Attachment failed for an unknown reason. Try again."
                )
            }
            return String(
                localized: "failure.message.unknown",
                defaultValue: "\(operation.displayName) failed for an unknown reason. Try again."
            )
        }
    }

    public static func coerce(
        _ error: any Error,
        operation: UserActionableFailureOperation,
        provider: String? = nil
    ) -> UserActionableFailure {
        if let failure = error as? UserActionableFailure {
            return failure
        }
        if let urlError = error as? URLError {
            return UserActionableFailure(
                category: urlError.userActionableCategory,
                operation: operation,
                provider: provider
            )
        }
        return UserActionableFailure(category: .unknown, operation: operation, provider: provider)
    }
}

private extension URLError {
    var userActionableCategory: UserActionableFailureCategory {
        switch code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed:
            return .offline
        default:
            return .providerUnavailable
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
