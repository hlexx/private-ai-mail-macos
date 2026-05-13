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
