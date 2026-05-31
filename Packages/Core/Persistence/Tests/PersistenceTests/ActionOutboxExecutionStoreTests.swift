import Foundation
import GRDB
import IntegrationDomain
import Testing
@testable import Persistence

@Suite("Action Outbox Execution Store")
struct ActionOutboxExecutionStoreTests {
    @Test func validTransitionFlowPersistsAttemptAuditAndResult() async throws {
        let db = try AppDatabase.openInMemorySync()
        try seedActionAccount(db)
        try insertActionOutboxRecord(
            db,
            opId: "op-success",
            idempotencyKey: "idem-success",
            payloadJSON: sensitivePayloadJSON
        )
        let executor = ProbeActionExecutor(result: ActionResult(
            status: .succeeded,
            externalResultId: "provider-result-1",
            completedAt: Date(timeIntervalSince1970: 200),
            metadata: .object(["provider": .string("local")])
        ))
        let store = ActionOutboxExecutionStore(
            db: db,
            executor: executor,
            now: { Date(timeIntervalSince1970: 100) },
            makeEventId: { UUID().uuidString }
        )

        let result = try await store.execute(opId: "op-success")

        #expect(result.status == ActionStatus.succeeded)
        #expect(await executor.executionCount == 1)

        try db.read { database in
            let fetchedRecord = try ActionOutboxRecord.fetchOne(database, key: "op-success")
            let record = try #require(fetchedRecord)
            #expect(record.status == "succeeded")
            #expect(record.attemptCount == 1)
            #expect(record.externalResultId == "provider-result-1")
            #expect(record.completedAt == 200)
            #expect(record.resultJSON?.contains("provider-result-1") == true)

            let attempts = try attemptsForOp("op-success", database)
            #expect(attempts.count == 1)
            #expect(attempts[0].attemptNumber == 1)
            #expect(attempts[0].status == "succeeded")
            #expect(attempts[0].completedAt == 100)

            let events = try auditEventsForOp("op-success", database)
            #expect(events.map(\.eventKind) == ["executionStarted", "executionSucceeded"])
            #expect(events.allSatisfy { isPrivacySafe($0.metadataJSON) })
            #expect(events[0].metadataJSON.contains("archiveThread"))
            #expect(events[1].metadataJSON.contains("hasExternalResult"))
        }
    }

    @Test func duplicateCompletedOpIdDoesNotExecuteProviderAgain() async throws {
        let db = try AppDatabase.openInMemorySync()
        try seedActionAccount(db)
        let completedResult = ActionResult(
            status: .succeeded,
            externalResultId: "provider-result-existing",
            completedAt: Date(timeIntervalSince1970: 90),
            metadata: .object(["provider": .string("local")])
        )
        try insertActionOutboxRecord(
            db,
            opId: "op-duplicate",
            idempotencyKey: "idem-duplicate",
            status: "succeeded",
            resultJSON: try encodeJSONString(completedResult),
            externalResultId: "provider-result-existing",
            completedAt: 90
        )
        let executor = ProbeActionExecutor(result: ActionResult(
            status: .failed,
            failureKind: .executionFailed
        ))
        let store = ActionOutboxExecutionStore(db: db, executor: executor)

        let result = try await store.execute(opId: "op-duplicate")

        #expect(result == completedResult)
        #expect(await executor.executionCount == 0)
        try db.read { database in
            #expect(try attemptsForOp("op-duplicate", database).isEmpty)
            let fetchedRecord = try ActionOutboxRecord.fetchOne(database, key: "op-duplicate")
            let record = try #require(fetchedRecord)
            #expect(record.status == "succeeded")
            #expect(record.attemptCount == 0)
        }
    }

    @Test func failedActionPersistenceRecordsRetryableFailureSafely() async throws {
        let db = try AppDatabase.openInMemorySync()
        try seedActionAccount(db)
        try insertActionOutboxRecord(
            db,
            opId: "op-failed",
            idempotencyKey: "idem-failed",
            payloadJSON: sensitivePayloadJSON
        )
        let executor = ProbeActionExecutor(result: ActionResult(
            status: .failed,
            failureKind: .networkUnavailable,
            metadata: .object(["provider": .string("local")])
        ))
        let store = ActionOutboxExecutionStore(
            db: db,
            executor: executor,
            now: { Date(timeIntervalSince1970: 110) },
            makeEventId: { UUID().uuidString }
        )

        let result = try await store.execute(opId: "op-failed")

        #expect(result.status == ActionStatus.failed)
        #expect(result.failureKind == ActionFailureKind.networkUnavailable)

        try db.read { database in
            let fetchedRecord = try ActionOutboxRecord.fetchOne(database, key: "op-failed")
            let record = try #require(fetchedRecord)
            #expect(record.status == "failed")
            #expect(record.lastErrorKind == "networkUnavailable")
            #expect(record.completedAt == nil)

            let attempts = try attemptsForOp("op-failed", database)
            #expect(attempts.count == 1)
            #expect(attempts[0].status == "failed")
            #expect(attempts[0].retryable == 1)
            #expect(attempts[0].errorCode == "networkUnavailable")
            #expect(isPrivacySafe(attempts[0].errorMessage ?? ""))

            let events = try auditEventsForOp("op-failed", database)
            #expect(events.map(\.eventKind) == ["executionStarted", "executionFailed"])
            #expect(events.allSatisfy { isPrivacySafe($0.metadataJSON) })
            #expect(events[1].metadataJSON.contains("networkUnavailable"))
            #expect(events[1].metadataJSON.contains("retryable"))
        }
    }

    @Test func nonRetryableFailurePersistsWithoutRetryFlag() async throws {
        let db = try AppDatabase.openInMemorySync()
        try seedActionAccount(db)
        try insertActionOutboxRecord(
            db,
            opId: "op-validation",
            idempotencyKey: "idem-validation"
        )
        let executor = ProbeActionExecutor(result: ActionResult(
            status: .failed,
            failureKind: .validationFailed
        ))
        let store = ActionOutboxExecutionStore(
            db: db,
            executor: executor,
            now: { Date(timeIntervalSince1970: 120) },
            makeEventId: { UUID().uuidString }
        )

        _ = try await store.execute(opId: "op-validation")

        try db.read { database in
            let fetchedRecord = try ActionOutboxRecord.fetchOne(database, key: "op-validation")
            let record = try #require(fetchedRecord)
            #expect(record.status == "failed")
            #expect(record.lastErrorKind == "validationFailed")

            let attempts = try attemptsForOp("op-validation", database)
            #expect(attempts.count == 1)
            #expect(attempts[0].retryable == 0)
            #expect(attempts[0].errorMessage == "The action request was invalid.")
        }
    }
}

private actor ProbeActionExecutor: ActionExecuting {
    private let result: ActionResult
    private var commands: [ActionCommand] = []

    init(result: ActionResult) {
        self.result = result
    }

    var executionCount: Int {
        commands.count
    }

    func execute(command: ActionCommand) async -> ActionResult {
        commands.append(command)
        return result
    }
}

private let sensitivePayloadJSON = """
{"schemaVersion":1,"body":{"body":"secret email body","prompt":"private prompt","token":"bearer-token"}}
"""

private func seedActionAccount(_ db: AppDatabase) throws {
    try db.dbQueue.write { database in
        try AccountRecord(
            id: "account-1",
            email: "user@example.test",
            displayName: "Example User",
            createdAt: 1
        ).insert(database)
    }
}

private func insertActionOutboxRecord(
    _ db: AppDatabase,
    opId: String,
    idempotencyKey: String,
    status: String = "ready",
    payloadJSON: String = #"{"schemaVersion":1,"body":{"reason":"userAction"}}"#,
    resultJSON: String? = nil,
    externalResultId: String? = nil,
    completedAt: Int? = nil
) throws {
    try db.dbQueue.write { database in
        try ActionOutboxRecord(
            opId: opId,
            accountId: "account-1",
            targetKind: "thread",
            threadId: "thread-1",
            actionKind: "archiveThread",
            actionSchemaVersion: 1,
            idempotencyKey: idempotencyKey,
            approvalRequirement: "notRequired",
            approvalState: "notRequired",
            status: status,
            payloadJSON: payloadJSON,
            resultJSON: resultJSON,
            externalResultId: externalResultId,
            createdAt: 10,
            updatedAt: 10,
            completedAt: completedAt
        ).insert(database)
    }
}

private func attemptsForOp(_ opId: String, _ database: Database) throws -> [ActionAttemptRecord] {
    try ActionAttemptRecord.fetchAll(
        database,
        sql: """
            SELECT * FROM action_attempt
            WHERE op_id = ?
            ORDER BY attempt_number
            """,
        arguments: [opId]
    )
}

private func auditEventsForOp(_ opId: String, _ database: Database) throws -> [ActionAuditEventRecord] {
    try ActionAuditEventRecord.fetchAll(
        database,
        sql: """
            SELECT * FROM action_audit_event
            WHERE op_id = ?
            ORDER BY occurred_at
            """,
        arguments: [opId]
    )
}

private func isPrivacySafe(_ value: String) -> Bool {
    !value.contains("secret email body")
        && !value.contains("private prompt")
        && !value.contains("bearer-token")
        && !value.lowercased().contains("token")
}

private func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}
