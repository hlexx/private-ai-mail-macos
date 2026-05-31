import Foundation
import GRDB
import IntegrationDomain

public enum ActionOutboxExecutionError: Error, Equatable, Sendable {
    case missingOutboxRecord(opId: String)
    case invalidActionKind(String)
    case invalidActionStatus(String)
    case invalidTarget(recordOpId: String)
    case invalidApprovalRequirement(String)
    case invalidApprovalState(String)
    case invalidActionSensitivity(String)
    case invalidFailureKind(String)
    case invalidDestinationKind(String)
    case invalidPayload(opId: String)
    case invalidResult(opId: String)
    case invalidJSONEncoding
    case actionNotReady(opId: String, status: String)
    case invalidTransition(opId: String, from: ActionStatus, to: ActionStatus)
}

public struct ActionOutboxExecutionStore: Sendable {
    let db: AppDatabase
    let executor: any ActionExecuting
    let now: @Sendable () -> Date
    let makeEventId: @Sendable () -> String

    public init(
        db: AppDatabase,
        executor: any ActionExecuting,
        now: @escaping @Sendable () -> Date = Date.init,
        makeEventId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.db = db
        self.executor = executor
        self.now = now
        self.makeEventId = makeEventId
    }

    public func execute(opId: String) async throws -> ActionResult {
        let prepared = try await db.write { database in
            try prepareExecution(opId: opId, database: database)
        }

        if let completed = prepared.completedResult {
            return completed
        }

        let result = await executor.execute(command: prepared.command)

        try await db.write { database in
            try completeExecution(
                opId: opId,
                attemptNumber: prepared.attemptNumber,
                result: result,
                database: database
            )
        }

        return result
    }
}

struct PreparedActionExecution: Sendable {
    let command: ActionCommand
    let attemptNumber: Int
    let completedResult: ActionResult?
}

extension ActionOutboxExecutionStore {
    func prepareExecution(opId: String, database: Database) throws -> PreparedActionExecution {
        var record = try fetchOutboxRecord(opId: opId, database: database)
        let currentStatus = try actionStatus(record.status)

        if currentStatus == .succeeded {
            return PreparedActionExecution(
                command: try command(from: record),
                attemptNumber: record.attemptCount,
                completedResult: try completedResult(from: record)
            )
        }

        guard currentStatus == .ready else {
            throw ActionOutboxExecutionError.actionNotReady(opId: opId, status: record.status)
        }
        guard currentStatus.canTransition(to: .executing) else {
            throw ActionOutboxExecutionError.invalidTransition(
                opId: opId,
                from: currentStatus,
                to: .executing
            )
        }

        let timestamp = currentTimestamp()
        let attemptNumber = record.attemptCount + 1
        record.status = ActionStatus.executing.rawValue
        record.attemptCount = attemptNumber
        record.updatedAt = timestamp
        try record.update(database)

        try ActionAttemptRecord(
            opId: opId,
            attemptNumber: attemptNumber,
            status: ActionStatus.executing.rawValue,
            startedAt: timestamp
        ).insert(database)

        try insertAuditEvent(
            opId: opId,
            kind: .executionStarted,
            actor: .executor,
            occurredAt: timestamp,
            metadata: auditMetadata(record: record, status: .executing),
            database: database
        )

        return PreparedActionExecution(
            command: try command(from: record),
            attemptNumber: attemptNumber,
            completedResult: nil
        )
    }

    func completeExecution(
        opId: String,
        attemptNumber: Int,
        result: ActionResult,
        database: Database
    ) throws {
        var record = try fetchOutboxRecord(opId: opId, database: database)
        let currentStatus = try actionStatus(record.status)
        guard currentStatus.canTransition(to: result.status) else {
            throw ActionOutboxExecutionError.invalidTransition(
                opId: opId,
                from: currentStatus,
                to: result.status
            )
        }

        let timestamp = currentTimestamp()
        record.status = result.status.rawValue
        record.resultJSON = try encodeJSONString(result)
        record.externalResultId = result.externalResultId
        record.lastErrorKind = result.failureKind?.rawValue
        record.updatedAt = timestamp
        if result.status == .succeeded {
            record.completedAt = result.completedAt.map(timestampValue) ?? timestamp
        }
        try record.update(database)

        var attempt = try fetchAttempt(
            opId: opId,
            attemptNumber: attemptNumber,
            database: database
        )
        attempt.status = result.status.rawValue
        attempt.completedAt = timestamp
        attempt.retryable = result.failureKind.map { $0.isRetryable ? 1 : 0 } ?? 0
        attempt.errorCode = result.failureKind?.rawValue
        attempt.errorMessage = result.failureKind.map(safeAttemptErrorMessage)
        try attempt.save(database)

        try insertAuditEvent(
            opId: opId,
            kind: auditKind(for: result),
            actor: .executor,
            occurredAt: timestamp,
            metadata: auditMetadata(record: record, result: result),
            database: database
        )
    }

    func fetchOutboxRecord(opId: String, database: Database) throws -> ActionOutboxRecord {
        guard let record = try ActionOutboxRecord.fetchOne(database, key: opId) else {
            throw ActionOutboxExecutionError.missingOutboxRecord(opId: opId)
        }
        return record
    }

    func fetchAttempt(
        opId: String,
        attemptNumber: Int,
        database: Database
    ) throws -> ActionAttemptRecord {
        try ActionAttemptRecord.fetchOne(
            database,
            key: ["op_id": opId, "attempt_number": attemptNumber]
        ) ?? ActionAttemptRecord(
            opId: opId,
            attemptNumber: attemptNumber,
            status: ActionStatus.executing.rawValue,
            startedAt: currentTimestamp()
        )
    }

    func currentTimestamp() -> Int {
        timestampValue(now())
    }

    func timestampValue(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970)
    }
}
