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
}
