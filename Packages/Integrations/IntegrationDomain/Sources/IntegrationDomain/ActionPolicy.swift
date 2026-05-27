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

    public func isAtLeastAsStrict(as minimum: ApprovalRequirement) -> Bool {
        strictnessRank >= minimum.strictnessRank
    }

    private var strictnessRank: Int {
        switch self {
        case .notRequired:
            0
        case .explicitUserApproval:
            1
        case .previewAndConfirm:
            2
        case .explicitConfirm:
            3
        }
    }
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
