import Foundation

public enum ActionSensitivity: String, CaseIterable, Codable, Hashable, Sendable {
    case standard
    case sensitive
}

public enum ApprovalRequirement: String, CaseIterable, Codable, Hashable, Sendable {
    case notRequired
    case explicitUserApproval
    case previewAndConfirm
    case explicitConfirm
}

public enum ApprovalState: String, CaseIterable, Codable, Hashable, Sendable {
    case notRequired
    case pending
    case approved
    case rejected
    case expired

    public static func initial(for requirement: ApprovalRequirement) -> ApprovalState {
        requirement == .notRequired ? .notRequired : .pending
    }

    public func satisfies(_ requirement: ApprovalRequirement) -> Bool {
        switch requirement {
        case .notRequired:
            self == .notRequired || self == .approved
        case .explicitUserApproval, .previewAndConfirm, .explicitConfirm:
            self == .approved
        }
    }
}

public enum ActionPolicy {
    public static func defaultApprovalRequirement(
        for kind: ActionKind,
        sensitivity: ActionSensitivity = .standard
    ) -> ApprovalRequirement {
        if sensitivity == .sensitive || kind.isDestructive {
            return .explicitConfirm
        }
        if kind.requiresSendApproval {
            return .explicitUserApproval
        }
        if kind.isExternalWrite {
            return .previewAndConfirm
        }
        return .notRequired
    }
}
