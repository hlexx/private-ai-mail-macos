import Foundation
import IntegrationDomain

extension ActionOutboxExecutionStore {
    func command(from record: ActionOutboxRecord) throws -> ActionCommand {
        try ActionCommand(
            opId: record.opId,
            accountId: record.accountId,
            target: target(from: record),
            kind: actionKind(record.actionKind),
            sensitivity: sensitivity(record.sensitivity),
            payload: payload(from: record),
            idempotencyKey: ActionIdempotencyKey(rawValue: record.idempotencyKey),
            approvalRequirement: approvalRequirement(record.approvalRequirement),
            approvalState: approvalState(record.approvalState),
            status: actionStatus(record.status),
            attemptCount: record.attemptCount,
            createdAt: Date(timeIntervalSince1970: TimeInterval(record.createdAt)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(record.updatedAt)),
            externalResultId: record.externalResultId
        )
    }

    func target(from record: ActionOutboxRecord) throws -> ActionTarget {
        switch record.targetKind {
        case ActionTargetKind.thread.rawValue:
            guard let threadId = record.threadId else {
                throw ActionOutboxExecutionError.invalidTarget(recordOpId: record.opId)
            }
            return .thread(accountId: record.accountId, threadId: threadId)
        case ActionTargetKind.message.rawValue:
            guard let threadId = record.threadId, let messageId = record.messageId else {
                throw ActionOutboxExecutionError.invalidTarget(recordOpId: record.opId)
            }
            return .message(accountId: record.accountId, threadId: threadId, messageId: messageId)
        case ActionTargetKind.attachment.rawValue:
            guard let messageId = record.messageId, let attachmentId = record.attachmentId else {
                throw ActionOutboxExecutionError.invalidTarget(recordOpId: record.opId)
            }
            return .attachment(accountId: record.accountId, messageId: messageId, attachmentId: attachmentId)
        case ActionTargetKind.integrationDestination.rawValue:
            return try integrationDestinationTarget(from: record)
        default:
            throw ActionOutboxExecutionError.invalidTarget(recordOpId: record.opId)
        }
    }

    func integrationDestinationTarget(from record: ActionOutboxRecord) throws -> ActionTarget {
        guard
            let rawDestinationKind = record.destinationKind,
            let destinationId = record.destinationId
        else {
            throw ActionOutboxExecutionError.invalidTarget(recordOpId: record.opId)
        }
        guard let destinationKind = IntegrationDestinationKind(rawValue: rawDestinationKind) else {
            throw ActionOutboxExecutionError.invalidDestinationKind(rawDestinationKind)
        }
        return .integrationDestination(
            accountId: record.accountId,
            destinationKind: destinationKind,
            destinationId: destinationId
        )
    }

    func payload(from record: ActionOutboxRecord) throws -> ActionPayload {
        do {
            return try JSONDecoder().decode(
                ActionPayload.self,
                from: Data(record.payloadJSON.utf8)
            )
        } catch {
            throw ActionOutboxExecutionError.invalidPayload(opId: record.opId)
        }
    }

    func completedResult(from record: ActionOutboxRecord) throws -> ActionResult {
        if let resultJSON = record.resultJSON {
            do {
                return try JSONDecoder().decode(
                    ActionResult.self,
                    from: Data(resultJSON.utf8)
                )
            } catch {
                throw ActionOutboxExecutionError.invalidResult(opId: record.opId)
            }
        }

        return ActionResult(
            status: .succeeded,
            externalResultId: record.externalResultId,
            completedAt: record.completedAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            },
            metadata: .object([
                "idempotency": .string("completedOpSuppressed"),
            ])
        )
    }

    func actionKind(_ value: String) throws -> ActionKind {
        guard let kind = ActionKind(rawValue: value) else {
            throw ActionOutboxExecutionError.invalidActionKind(value)
        }
        return kind
    }

    func actionStatus(_ value: String) throws -> ActionStatus {
        guard let status = ActionStatus(rawValue: value) else {
            throw ActionOutboxExecutionError.invalidActionStatus(value)
        }
        return status
    }

    func sensitivity(_ value: String) throws -> ActionSensitivity {
        guard let sensitivity = ActionSensitivity(rawValue: value) else {
            throw ActionOutboxExecutionError.invalidActionSensitivity(value)
        }
        return sensitivity
    }

    func approvalRequirement(_ value: String) throws -> ApprovalRequirement {
        guard let requirement = ApprovalRequirement(rawValue: value) else {
            throw ActionOutboxExecutionError.invalidApprovalRequirement(value)
        }
        return requirement
    }

    func approvalState(_ value: String) throws -> ApprovalState {
        guard let state = ApprovalState(rawValue: value) else {
            throw ActionOutboxExecutionError.invalidApprovalState(value)
        }
        return state
    }
}
