import Foundation

public enum ActionCommandValidationError: Error, Equatable, Sendable {
    case accountMismatch(commandAccountId: String, targetAccountId: String)
    case approvalRequirementTooWeak(
        kind: ActionKind,
        minimum: ApprovalRequirement,
        provided: ApprovalRequirement
    )
    case statusRequiresSatisfiedApproval(
        status: ActionStatus,
        requirement: ApprovalRequirement,
        state: ApprovalState
    )
}

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
    ) throws {
        guard accountId == target.accountId else {
            throw ActionCommandValidationError.accountMismatch(
                commandAccountId: accountId,
                targetAccountId: target.accountId
            )
        }

        let defaultRequirement = ActionPolicy.defaultApprovalRequirement(for: kind)
        let requirement = approvalRequirement ?? defaultRequirement
        let state = approvalState ?? ApprovalState.initial(for: requirement)
        let commandStatus = status ?? ActionStatus.initial(for: state)
        try Self.validateApprovalPolicy(
            kind: kind,
            defaultRequirement: defaultRequirement,
            requirement: requirement,
            state: state,
            status: commandStatus
        )

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
            userActionId: userActionId ?? opId
        )
        self.approvalRequirement = requirement
        self.approvalState = state
        self.status = commandStatus
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.externalResultId = externalResultId
    }

    enum CodingKeys: String, CodingKey {
        case opId
        case accountId
        case target
        case kind
        case schemaVersion
        case payload
        case idempotencyKey
        case approvalRequirement
        case approvalState
        case status
        case attemptCount
        case createdAt
        case updatedAt
        case externalResultId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let accountId = try container.decode(String.self, forKey: .accountId)
        let target = try container.decode(ActionTarget.self, forKey: .target)
        guard accountId == target.accountId else {
            throw ActionCommandValidationError.accountMismatch(
                commandAccountId: accountId,
                targetAccountId: target.accountId
            )
        }

        opId = try container.decode(String.self, forKey: .opId)
        self.accountId = accountId
        self.target = target
        let decodedKind = try container.decode(ActionKind.self, forKey: .kind)
        let decodedRequirement = try container.decode(ApprovalRequirement.self, forKey: .approvalRequirement)
        let decodedState = try container.decode(ApprovalState.self, forKey: .approvalState)
        let decodedStatus = try container.decode(ActionStatus.self, forKey: .status)
        try Self.validateApprovalPolicy(
            kind: decodedKind,
            defaultRequirement: ActionPolicy.defaultApprovalRequirement(for: decodedKind),
            requirement: decodedRequirement,
            state: decodedState,
            status: decodedStatus
        )

        kind = decodedKind
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        payload = try container.decode(ActionPayload.self, forKey: .payload)
        idempotencyKey = try container.decode(ActionIdempotencyKey.self, forKey: .idempotencyKey)
        approvalRequirement = decodedRequirement
        approvalState = decodedState
        status = decodedStatus
        attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        externalResultId = try container.decodeIfPresent(String.self, forKey: .externalResultId)
    }

    private static func validateApprovalPolicy(
        kind: ActionKind,
        defaultRequirement: ApprovalRequirement,
        requirement: ApprovalRequirement,
        state: ApprovalState,
        status: ActionStatus
    ) throws {
        guard requirement.isAtLeastAsStrict(as: defaultRequirement) else {
            throw ActionCommandValidationError.approvalRequirementTooWeak(
                kind: kind,
                minimum: defaultRequirement,
                provided: requirement
            )
        }

        guard status.requiresSatisfiedApproval == false || state.satisfies(requirement) else {
            throw ActionCommandValidationError.statusRequiresSatisfiedApproval(
                status: status,
                requirement: requirement,
                state: state
            )
        }
    }
}

private extension ActionStatus {
    var requiresSatisfiedApproval: Bool {
        switch self {
        case .ready, .executing, .succeeded:
            true
        case .pending, .failed, .cancelled, .blocked:
            false
        }
    }
}
