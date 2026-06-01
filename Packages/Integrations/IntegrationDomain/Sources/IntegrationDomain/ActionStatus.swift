import Foundation

public enum ActionStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case pending
    case ready
    case executing
    case succeeded
    case failed
    case cancelled
    case blocked

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .cancelled:
            true
        case .pending, .ready, .executing, .failed, .blocked:
            false
        }
    }

    public static func initial(for approvalState: ApprovalState) -> ActionStatus {
        approvalState == .notRequired || approvalState == .approved ? .ready : .pending
    }

    public func canTransition(to next: ActionStatus) -> Bool {
        switch (self, next) {
        case (.pending, .ready), (.pending, .blocked), (.pending, .cancelled):
            true
        case (.ready, .executing), (.ready, .blocked), (.ready, .cancelled):
            true
        case (.executing, .succeeded), (.executing, .failed), (.executing, .blocked), (.executing, .cancelled):
            true
        case (.failed, .ready), (.failed, .cancelled):
            true
        case (.blocked, .ready), (.blocked, .cancelled):
            true
        default:
            false
        }
    }
}
