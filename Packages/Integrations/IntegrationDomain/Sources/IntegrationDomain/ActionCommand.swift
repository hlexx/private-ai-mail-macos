import Foundation

public struct ActionCommand: Codable, Equatable, Hashable, Sendable {
    public let opId: String
    public let accountId: String
    public let target: ActionTarget
    public let kind: ActionKind
    public let schemaVersion: Int
    public let payload: ActionPayload
    public let idempotencyKey: ActionIdempotencyKey
    public let approvalRequirement: ApprovalRequirement
    public let approvalState: ApprovalState
    public let status: ActionStatus
    public let attemptCount: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let externalResultId: String?

    public init(
        opId: String,
        accountId: String,
        target: ActionTarget,
        kind: ActionKind,
        payload: ActionPayload = ActionPayload(),
        userActionId: String? = nil,
        idempotencyKey: ActionIdempotencyKey? = nil,
        approvalRequirement: ApprovalRequirement? = nil,
        approvalState: ApprovalState? = nil,
        status: ActionStatus? = nil,
        attemptCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        externalResultId: String? = nil
    ) {
        let requirement = approvalRequirement ?? ActionPolicy.defaultApprovalRequirement(for: kind)
        let state = approvalState ?? ApprovalState.initial(for: requirement)
        self.opId = opId
        self.accountId = accountId
        self.target = target
        self.kind = kind
        self.schemaVersion = payload.schemaVersion
        self.payload = payload
        self.idempotencyKey = idempotencyKey ?? ActionIdempotencyKey.make(
            accountId: accountId,
            kind: kind,
            target: target,
            schemaVersion: payload.schemaVersion,
            userActionId: userActionId
        )
        self.approvalRequirement = requirement
        self.approvalState = state
        self.status = status ?? ActionStatus.initial(for: state)
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.externalResultId = externalResultId
    }
}
