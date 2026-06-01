import Foundation

public enum ActionFailureKind: String, CaseIterable, Codable, Hashable, Sendable {
    case policyDenied
    case approvalMissing
    case validationFailed
    case authenticationRequired
    case permissionDenied
    case rateLimited
    case networkUnavailable
    case providerRejected
    case executionFailed
    case cancelled
    case unknown

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .networkUnavailable, .executionFailed, .unknown:
            true
        case .policyDenied, .approvalMissing, .validationFailed, .authenticationRequired,
             .permissionDenied, .providerRejected, .cancelled:
            false
        }
    }
}
