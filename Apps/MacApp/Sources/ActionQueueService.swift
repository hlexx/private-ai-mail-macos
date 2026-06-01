import ActionsFeature
import Foundation
import GRDB
import IntegrationDomain
import MailSync
import Persistence

@MainActor
final class ActionQueueService: TrustActionQueueing {
    private let db: AppDatabase
    private let executionStore: ActionOutboxExecutionStore
    private let now: @Sendable () -> Date

    init(
        db: AppDatabase,
        executionStore: ActionOutboxExecutionStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.db = db
        self.executionStore = executionStore
        self.now = now
    }

    func start(_ request: TrustActionRequest) async -> TrustActionQueueOutcome {
        do {
            if request.action == .draftReply {
                return try await completeLocalDraftRequest(request)
            }

            try await enqueue(request)
            let result = try await executionStore.execute(opId: request.requestId)
            return Self.outcome(opId: request.requestId, result: result)
        } catch {
            return TrustActionQueueOutcome(
                opId: request.requestId,
                status: .failedNonRetryable,
                failureKind: .validationFailed,
                message: TrustActionFailureCopy.message(for: .validationFailed)
            )
        }
    }

    func retry(opId: String) async -> TrustActionQueueOutcome? {
        do {
            guard try await prepareRetry(opId: opId) else { return nil }
            let result = try await executionStore.execute(opId: opId)
            return Self.outcome(opId: opId, result: result)
        } catch {
            return TrustActionQueueOutcome(
                opId: opId,
                status: .failedRetryable,
                failureKind: .unknown,
                message: TrustActionFailureCopy.message(for: .unknown)
            )
        }
    }

    private func enqueue(_ request: TrustActionRequest) async throws {
        let timestamp = timestampValue(now())
        let command = try command(for: request, timestamp: timestamp)
        let payloadJSON = try encodeJSONString(command.payload)
        try await db.write { database in
            if try ActionOutboxRecord.fetchOne(database, key: request.requestId) != nil {
                return
            }
            try ActionOutboxRecord(
                opId: command.opId,
                accountId: command.accountId,
                targetKind: command.target.kind.rawValue,
                threadId: request.target.threadId,
                actionKind: command.kind.rawValue,
                sensitivity: command.sensitivity.rawValue,
                actionSchemaVersion: command.schemaVersion,
                idempotencyKey: command.idempotencyKey.rawValue,
                approvalRequirement: command.approvalRequirement.rawValue,
                approvalState: command.approvalState.rawValue,
                status: command.status.rawValue,
                payloadJSON: payloadJSON,
                attemptCount: command.attemptCount,
                createdAt: timestamp,
                updatedAt: timestamp,
                approvedAt: timestamp
            ).insert(database)
        }
    }

    private func completeLocalDraftRequest(_ request: TrustActionRequest) async throws -> TrustActionQueueOutcome {
        let timestamp = timestampValue(now())
        let command = try command(for: request, timestamp: timestamp, status: .succeeded)
        let result = ActionResult(
            status: .succeeded,
            externalResultId: "local:draft:\(request.requestId)",
            completedAt: now(),
            metadata: .object([
                "actionKind": .string(request.action.rawValue),
                "executor": .string("local-ui"),
                "result": .string("approved"),
                "targetKind": .string(command.target.kind.rawValue),
            ])
        )
        let payloadJSON = try encodeJSONString(command.payload)
        let resultJSON = try encodeJSONString(result)
        try await db.write { database in
            if try ActionOutboxRecord.fetchOne(database, key: request.requestId) != nil {
                return
            }
            try ActionOutboxRecord(
                opId: command.opId,
                accountId: command.accountId,
                targetKind: command.target.kind.rawValue,
                threadId: request.target.threadId,
                actionKind: command.kind.rawValue,
                sensitivity: command.sensitivity.rawValue,
                actionSchemaVersion: command.schemaVersion,
                idempotencyKey: command.idempotencyKey.rawValue,
                approvalRequirement: command.approvalRequirement.rawValue,
                approvalState: command.approvalState.rawValue,
                status: command.status.rawValue,
                payloadJSON: payloadJSON,
                resultJSON: resultJSON,
                externalResultId: result.externalResultId,
                attemptCount: command.attemptCount,
                createdAt: timestamp,
                updatedAt: timestamp,
                approvedAt: timestamp,
                completedAt: timestamp
            ).insert(database)
        }

        return TrustActionQueueOutcome(
            opId: request.requestId,
            status: .completed,
            message: "Draft action approved"
        )
    }

    private func prepareRetry(opId: String) async throws -> Bool {
        let timestamp = timestampValue(now())
        return try await db.write { database in
            guard var record = try ActionOutboxRecord.fetchOne(database, key: opId),
                  record.status == ActionStatus.failed.rawValue,
                  TrustActionFailureCopy.isRetryable(record.lastErrorKind.flatMap(ActionFailureKind.init(rawValue:))) else {
                return false
            }
            record.status = ActionStatus.ready.rawValue
            record.approvalState = ApprovalState.approved.rawValue
            record.updatedAt = timestamp
            try record.update(database)
            return true
        }
    }

    private func command(
        for request: TrustActionRequest,
        timestamp: Int,
        status: ActionStatus = .ready
    ) throws -> ActionCommand {
        try ActionCommand(
            opId: request.requestId,
            accountId: request.target.accountId,
            target: .thread(accountId: request.target.accountId, threadId: request.target.threadId),
            kind: request.action.kind,
            sensitivity: request.action == .trashThread ? .sensitive : .standard,
            payload: ActionPayload(body: .object([
                "source": .string("user"),
                "surface": .string("trustMVP"),
            ])),
            userActionId: request.requestId,
            approvalRequirement: request.action.requiresExplicitConfirmation ? .explicitConfirm : .notRequired,
            approvalState: request.action.requiresExplicitConfirmation ? .approved : .notRequired,
            status: status,
            createdAt: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(timestamp))
        )
    }

    private func encodeJSONString(_ value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ActionQueueServiceError.invalidJSONEncoding
        }
        return json
    }

    private func timestampValue(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970)
    }

    private static func outcome(opId: String, result: ActionResult) -> TrustActionQueueOutcome {
        switch result.status {
        case .succeeded:
            return TrustActionQueueOutcome(
                opId: opId,
                status: .completed,
                message: "Action completed"
            )
        case .failed:
            let retryable = TrustActionFailureCopy.isRetryable(result.failureKind)
            return TrustActionQueueOutcome(
                opId: opId,
                status: retryable ? .failedRetryable : .failedNonRetryable,
                failureKind: result.failureKind,
                message: TrustActionFailureCopy.message(for: result.failureKind)
            )
        case .pending:
            return TrustActionQueueOutcome(opId: opId, status: .pending, message: "Queued action")
        case .ready, .executing:
            return TrustActionQueueOutcome(opId: opId, status: .running, message: "Running action")
        case .cancelled, .blocked:
            return TrustActionQueueOutcome(
                opId: opId,
                status: .failedNonRetryable,
                failureKind: .cancelled,
                message: TrustActionFailureCopy.message(for: .cancelled)
            )
        }
    }
}

private enum ActionQueueServiceError: Error {
    case invalidJSONEncoding
}
