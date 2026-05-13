import Foundation

public enum SyncState: String, Sendable, Equatable {
    case idle
    case bootstrapping
    case live
    case paused
    case degraded
}
