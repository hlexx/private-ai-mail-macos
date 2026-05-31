import Foundation
import GRDB
import IntegrationDomain

extension ActionOutboxExecutionStore {
    func insertAuditEvent(
        opId: String,
        kind: ActionAuditEvent.Kind,
        actor: ActionAuditEvent.ActorKind,
        occurredAt: Int,
        metadata: JSONValue,
        database: Database
    ) throws {
        try ActionAuditEventRecord(
            eventId: makeEventId(),
            opId: opId,
            eventKind: kind.rawValue,
            actorKind: actor.rawValue,
            occurredAt: occurredAt,
            metadataJSON: try encodeJSONString(metadata)
        ).insert(database)
    }

    func auditMetadata(record: ActionOutboxRecord, status: ActionStatus) -> JSONValue {
        .object([
            "actionKind": .string(record.actionKind),
            "status": .string(status.rawValue),
            "targetKind": .string(record.targetKind),
        ])
    }

    func auditMetadata(record: ActionOutboxRecord, result: ActionResult) -> JSONValue {
        var metadata: [String: JSONValue] = [
            "actionKind": .string(record.actionKind),
            "status": .string(result.status.rawValue),
            "targetKind": .string(record.targetKind),
        ]
        if let failureKind = result.failureKind {
            metadata["failureKind"] = .string(failureKind.rawValue)
            metadata["retryable"] = .bool(failureKind.isRetryable)
        }
        if result.externalResultId != nil {
            metadata["hasExternalResult"] = .bool(true)
        }
        return .object(metadata)
    }

    func auditKind(for result: ActionResult) -> ActionAuditEvent.Kind {
        switch result.status {
        case .succeeded:
            .executionSucceeded
        case .blocked:
            .blocked
        case .cancelled:
            .cancelled
        case .failed, .pending, .ready, .executing:
            .executionFailed
        }
    }

    func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ActionOutboxExecutionError.invalidJSONEncoding
        }
        return string
    }

    func safeAttemptErrorMessage(for failureKind: ActionFailureKind) -> String {
        switch failureKind {
        case .authenticationRequired:
            "Authentication is required before this action can run."
        case .permissionDenied:
            "The provider denied permission for this action."
        case .rateLimited:
            "The provider rate limited this action."
        case .networkUnavailable:
            "The network was unavailable while running this action."
        case .providerRejected:
            "The provider rejected this action."
        case .policyDenied:
            "Policy denied this action."
        case .approvalMissing:
            "Approval is required before this action can run."
        case .validationFailed:
            "The action request was invalid."
        case .executionFailed:
            "The action failed while running."
        case .cancelled:
            "The action was cancelled."
        case .unknown:
            "The action failed for an unknown reason."
        }
    }
}

extension ActionFailureKind {
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .networkUnavailable, .executionFailed, .unknown:
            true
        case .policyDenied, .approvalMissing, .validationFailed, .authenticationRequired,
             .permissionDenied, .providerRejected, .cancelled:
            false
        }
    }
}
