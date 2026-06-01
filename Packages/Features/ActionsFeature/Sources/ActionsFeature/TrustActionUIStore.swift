import Foundation
import IntegrationDomain
import Observation

public enum TrustMVPAction: String, CaseIterable, Identifiable, Sendable, Hashable {
    case draftReply
    case archiveThread
    case starThread
    case markRead
    case trashThread

    public var id: String { rawValue }

    public var kind: ActionKind {
        switch self {
        case .draftReply: .draftReply
        case .archiveThread: .archiveThread
        case .starThread: .starThread
        case .markRead: .markRead
        case .trashThread: .trashThread
        }
    }

    public var requiresExplicitConfirmation: Bool {
        switch self {
        case .draftReply, .trashThread:
            true
        case .archiveThread, .starThread, .markRead:
            false
        }
    }

    public var title: String {
        switch self {
        case .draftReply: "Draft reply"
        case .archiveThread: "Archive"
        case .starThread: "Star"
        case .markRead: "Mark read"
        case .trashThread: "Trash"
        }
    }

    public var systemImage: String {
        switch self {
        case .draftReply: "arrowshape.turn.up.left"
        case .archiveThread: "archivebox"
        case .starThread: "star"
        case .markRead: "envelope.open"
        case .trashThread: "trash"
        }
    }
}

public struct TrustActionTarget: Equatable, Hashable, Sendable {
    public let accountId: String
    public let threadId: String
    public let subject: String

    public init(accountId: String, threadId: String, subject: String = "") {
        self.accountId = accountId
        self.threadId = threadId
        self.subject = subject
    }
}

public struct TrustActionRequest: Equatable, Hashable, Sendable {
    public let requestId: String
    public let action: TrustMVPAction
    public let target: TrustActionTarget
    public let createdByAIOutput: Bool

    public init(
        requestId: String = UUID().uuidString,
        action: TrustMVPAction,
        target: TrustActionTarget,
        createdByAIOutput: Bool = false
    ) {
        self.requestId = requestId
        self.action = action
        self.target = target
        self.createdByAIOutput = createdByAIOutput
    }
}

public enum TrustActionDisplayStatus: Equatable, Hashable, Sendable {
    case pending
    case running
    case completed
    case failedRetryable
    case failedNonRetryable

    public var label: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .completed: "Completed"
        case .failedRetryable: "Retry available"
        case .failedNonRetryable: "Failed"
        }
    }
}

public struct TrustActionOutboxItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let action: TrustMVPAction
    public let target: TrustActionTarget
    public var status: TrustActionDisplayStatus
    public var failureKind: ActionFailureKind?
    public var message: String

    public init(
        id: String,
        action: TrustMVPAction,
        target: TrustActionTarget,
        status: TrustActionDisplayStatus,
        failureKind: ActionFailureKind? = nil,
        message: String
    ) {
        self.id = id
        self.action = action
        self.target = target
        self.status = status
        self.failureKind = failureKind
        self.message = message
    }

    public var canRetry: Bool {
        status == .failedRetryable
    }
}

public struct TrustActionQueueOutcome: Equatable, Hashable, Sendable {
    public let opId: String
    public let status: TrustActionDisplayStatus
    public let failureKind: ActionFailureKind?
    public let message: String

    public init(
        opId: String,
        status: TrustActionDisplayStatus,
        failureKind: ActionFailureKind? = nil,
        message: String
    ) {
        self.opId = opId
        self.status = status
        self.failureKind = failureKind
        self.message = message
    }
}

@MainActor
public protocol TrustActionQueueing: AnyObject {
    func start(_ request: TrustActionRequest) async -> TrustActionQueueOutcome
    func retry(opId: String) async -> TrustActionQueueOutcome?
}

public struct PendingTrustActionApproval: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let request: TrustActionRequest

    public init(request: TrustActionRequest) {
        self.id = request.requestId
        self.request = request
    }

    public var title: String {
        switch request.action {
        case .draftReply:
            "Create draft?"
        case .trashThread:
            "Move thread to trash?"
        case .archiveThread, .starThread, .markRead:
            "\(request.action.title)?"
        }
    }

    public var message: String {
        switch request.action {
        case .draftReply:
            "A draft action can write provider state. Review before continuing."
        case .trashThread:
            "This removes the thread from the inbox and moves it to trash."
        case .archiveThread, .starThread, .markRead:
            "This updates only mailbox labels for the selected thread."
        }
    }
}

@Observable
@MainActor
public final class TrustActionUIStore {
    public private(set) var pendingApproval: PendingTrustActionApproval?
    public private(set) var outboxItems: [TrustActionOutboxItem] = []

    private let queue: any TrustActionQueueing

    public init(queue: any TrustActionQueueing) {
        self.queue = queue
    }

    public func requestAction(_ request: TrustActionRequest) async {
        guard !request.createdByAIOutput else { return }
        if request.action.requiresExplicitConfirmation {
            pendingApproval = PendingTrustActionApproval(request: request)
            return
        }
        await start(request)
    }

    public func confirmPendingAction() async {
        guard let approval = pendingApproval else { return }
        pendingApproval = nil
        await start(approval.request)
    }

    public func cancelPendingAction() {
        pendingApproval = nil
    }

    public func retry(opId: String) async {
        guard let index = outboxItems.firstIndex(where: { $0.id == opId }),
              outboxItems[index].canRetry else {
            return
        }
        outboxItems[index].status = .running
        outboxItems[index].message = "Retrying action"
        guard let outcome = await queue.retry(opId: opId) else {
            return
        }
        apply(outcome, fallbackRequest: outboxItems[index])
    }

    public func replaceOutboxItems(_ items: [TrustActionOutboxItem]) {
        outboxItems = items
    }

    private func start(_ request: TrustActionRequest) async {
        let pending = TrustActionOutboxItem(
            id: request.requestId,
            action: request.action,
            target: request.target,
            status: .pending,
            message: "Queued action"
        )
        upsert(pending)
        update(id: request.requestId, status: .running, message: "Running action")
        let outcome = await queue.start(request)
        apply(outcome, fallbackRequest: pending)
    }

    private func apply(_ outcome: TrustActionQueueOutcome, fallbackRequest: TrustActionOutboxItem) {
        var item = fallbackRequest
        item = TrustActionOutboxItem(
            id: outcome.opId,
            action: fallbackRequest.action,
            target: fallbackRequest.target,
            status: outcome.status,
            failureKind: outcome.failureKind,
            message: outcome.message
        )
        upsert(item)
    }

    private func update(id: String, status: TrustActionDisplayStatus, message: String) {
        guard let index = outboxItems.firstIndex(where: { $0.id == id }) else { return }
        outboxItems[index].status = status
        outboxItems[index].message = message
    }

    private func upsert(_ item: TrustActionOutboxItem) {
        if let index = outboxItems.firstIndex(where: { $0.id == item.id }) {
            outboxItems[index] = item
        } else {
            outboxItems.insert(item, at: 0)
        }
    }
}

public enum TrustActionFailureCopy {
    public static func message(for failureKind: ActionFailureKind?) -> String {
        guard let failureKind else { return "Action failed. Try again later." }
        switch failureKind {
        case .authenticationRequired:
            return "Reconnect the account, then retry this action."
        case .permissionDenied:
            return "The account is missing permission for this action."
        case .rateLimited:
            return "The provider is rate limiting actions. Retry shortly."
        case .networkUnavailable:
            return "Network is unavailable. Retry when the connection returns."
        case .providerRejected:
            return "The provider rejected this action."
        case .executionFailed:
            return "The provider could not complete this action. Retry is available."
        case .policyDenied:
            return "Policy blocked this action."
        case .approvalMissing:
            return "Approve this action before running it."
        case .validationFailed:
            return "The action request is invalid."
        case .cancelled:
            return "The action was cancelled."
        case .unknown:
            return "Action failed. Retry is available."
        }
    }

    public static func isRetryable(_ failureKind: ActionFailureKind?) -> Bool {
        switch failureKind {
        case .rateLimited, .networkUnavailable, .executionFailed, .unknown:
            return true
        case .authenticationRequired, .permissionDenied, .providerRejected, .policyDenied,
             .approvalMissing, .validationFailed, .cancelled, nil:
            return false
        }
    }
}
