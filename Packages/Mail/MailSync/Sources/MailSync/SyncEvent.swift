import Foundation

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
        switch self {
        case .bootstrapFailed(let inner):
            // Surface the underlying error verbatim. Without this, the UI
            // falls back to Swift's default Error bridging and renders
            // "The operation couldn't be completed. (MailSync.SyncError
            // error 0.)" — useless for diagnosing what actually broke.
            return "Bootstrap sync failed: \(describe(inner))"
        case .incrementalFailed(let inner):
            return "Incremental sync failed: \(describe(inner))"
        case .rateLimited(let retryAfter):
            return "Gmail API rate limit hit. Retrying in \(Int(retryAfter))s."
        case .historyExpired:
            return "Gmail history token expired; falling back to a full sync."
        }
    }

    private func describe(_ error: any Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }
}
