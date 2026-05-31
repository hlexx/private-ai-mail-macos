import GRDB
import Testing
@testable import Persistence

@Suite("Action Outbox Migration")
struct ActionOutboxMigrationTests {
    @Test func freshMigrationCreatesActionOutboxTablesAndIndexes() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.read { database in
            let tables = try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            #expect(tables.contains("action_outbox"))
            #expect(tables.contains("action_attempt"))
            #expect(tables.contains("action_audit_event"))

            let outboxColumns = try actionTableColumns("action_outbox", database)
            #expect(outboxColumns.isSuperset(of: [
                "op_id", "account_id", "target_kind", "thread_id",
                "message_id", "attachment_id", "destination_kind",
                "destination_id", "action_kind", "action_schema_version",
                "idempotency_key", "sensitivity", "approval_requirement",
                "approval_state", "status", "payload_json", "result_json",
                "external_result_id", "last_error_kind", "last_error_code",
                "attempt_count", "created_at", "updated_at", "approved_at",
                "completed_at",
            ]))

            let attemptColumns = try actionTableColumns("action_attempt", database)
            #expect(attemptColumns.isSuperset(of: [
                "op_id", "attempt_number", "status", "started_at",
                "completed_at", "retryable", "error_code", "error_message",
            ]))

            let auditColumns = try actionTableColumns("action_audit_event", database)
            #expect(auditColumns.isSuperset(of: [
                "event_id", "op_id", "event_kind", "actor_kind",
                "occurred_at", "metadata_json",
            ]))

            let indexes = try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
            #expect(indexes.contains("idx_action_outbox_account_status"))
            #expect(indexes.contains("idx_action_outbox_idempotency_key"))
            #expect(indexes.contains("idx_action_outbox_target"))
            #expect(indexes.contains("idx_action_outbox_updated_at"))
            #expect(indexes.contains("idx_action_attempt_order"))
            #expect(indexes.contains("idx_action_audit_event_order"))
        }
    }

    @Test func duplicateIdempotencyKeyIsRejected() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.write { database in
            try seedAccount(database)
            try makeOutboxRecord(opId: "op-1", idempotencyKey: "idem-1").insert(database)

            var rejectedDuplicate = false
            do {
                try makeOutboxRecord(opId: "op-2", idempotencyKey: "idem-1").insert(database)
            } catch {
                rejectedDuplicate = true
            }

            #expect(rejectedDuplicate)
            #expect(try ActionOutboxRecord.fetchCount(database) == 1)
        }
    }

    @Test func outboxSensitivityPersistsAndDefaultsToStandard() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.write { database in
            try seedAccount(database)

            var sensitiveRecord = makeOutboxRecord(opId: "op-sensitive", idempotencyKey: "idem-sensitive")
            sensitiveRecord.sensitivity = "sensitive"
            try sensitiveRecord.insert(database)

            let fetchedRecord = try ActionOutboxRecord.fetchOne(database, key: "op-sensitive")
            let fetched = try #require(fetchedRecord)
            #expect(fetched.sensitivity == "sensitive")

            try database.execute(
                sql: """
                    INSERT INTO action_outbox (
                        op_id, account_id, target_kind, thread_id, action_kind,
                        action_schema_version, idempotency_key, approval_requirement,
                        approval_state, status, payload_json, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "op-default", "account-1", "thread", "thread-1", "archiveThread",
                    "1", "idem-default", "notRequired", "notRequired", "ready",
                    #"{"schemaVersion":1,"body":{}}"#, "10", "10",
                ]
            )

            let defaultedRecord = try ActionOutboxRecord.fetchOne(database, key: "op-default")
            let defaulted = try #require(defaultedRecord)
            #expect(defaulted.sensitivity == "standard")
        }
    }

    @Test func statusTransitionPersistenceRoundTrips() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.write { database in
            try seedAccount(database)
            var outbox = makeOutboxRecord(opId: "op-status", idempotencyKey: "idem-status")
            try outbox.insert(database)

            outbox.approvalState = "approved"
            outbox.status = "executing"
            outbox.updatedAt = 20
            outbox.approvedAt = 19
            outbox.attemptCount = 1
            try outbox.update(database)

            let fetchedRecord = try ActionOutboxRecord.fetchOne(database, key: "op-status")
            var fetched = try #require(fetchedRecord)
            #expect(fetched.status == "executing")
            #expect(fetched.approvalState == "approved")
            #expect(fetched.attemptCount == 1)
            #expect(fetched.approvedAt == 19)

            fetched.status = "succeeded"
            fetched.resultJSON = #"{"queued":false,"provider":"local"}"#
            fetched.externalResultId = "local-result-1"
            fetched.completedAt = 30
            fetched.updatedAt = 30
            try fetched.update(database)

            let completedRecord = try ActionOutboxRecord.fetchOne(database, key: "op-status")
            let completed = try #require(completedRecord)
            #expect(completed.status == "succeeded")
            #expect(completed.resultJSON == #"{"queued":false,"provider":"local"}"#)
            #expect(completed.externalResultId == "local-result-1")
            #expect(completed.completedAt == 30)
        }
    }

    @Test func attemptsPersistInAttemptNumberOrder() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.write { database in
            try seedAccount(database)
            try makeOutboxRecord(opId: "op-attempt", idempotencyKey: "idem-attempt").insert(database)
            try ActionAttemptRecord(
                opId: "op-attempt",
                attemptNumber: 2,
                status: "succeeded",
                startedAt: 30,
                completedAt: 40
            ).insert(database)
            try ActionAttemptRecord(
                opId: "op-attempt",
                attemptNumber: 1,
                status: "failed",
                startedAt: 10,
                completedAt: 20,
                retryable: 1,
                errorCode: "networkUnavailable",
                errorMessage: "retryable transport failure"
            ).insert(database)

            let attempts = try ActionAttemptRecord.fetchAll(
                database,
                sql: """
                    SELECT * FROM action_attempt
                    WHERE op_id = ?
                    ORDER BY attempt_number
                    """,
                arguments: ["op-attempt"]
            )

            #expect(attempts.map(\.attemptNumber) == [1, 2])
            #expect(attempts.first?.retryable == 1)
            #expect(attempts.first?.errorCode == "networkUnavailable")
            #expect(attempts.last?.status == "succeeded")
        }
    }

    @Test func auditEventsPersistWithPrivacySafeMetadata() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.write { database in
            try seedAccount(database)
            try makeOutboxRecord(opId: "op-audit", idempotencyKey: "idem-audit").insert(database)
            try ActionAuditEventRecord(
                eventId: "event-2",
                opId: "op-audit",
                eventKind: "queued",
                actorKind: "system",
                occurredAt: 20,
                metadataJSON: #"{"status":"ready"}"#
            ).insert(database)
            try ActionAuditEventRecord(
                eventId: "event-1",
                opId: "op-audit",
                eventKind: "created",
                actorKind: "user",
                occurredAt: 10,
                metadataJSON: #"{"target":"thread-1"}"#
            ).insert(database)

            let events = try ActionAuditEventRecord.fetchAll(
                database,
                sql: """
                    SELECT * FROM action_audit_event
                    WHERE op_id = ?
                    ORDER BY occurred_at
                    """,
                arguments: ["op-audit"]
            )

            #expect(events.map(\.eventId) == ["event-1", "event-2"])
            #expect(events.first?.metadataJSON == #"{"target":"thread-1"}"#)
            #expect(events.last?.metadataJSON == #"{"status":"ready"}"#)
        }
    }

    @Test func accountDeletionCascadesOutboxAttemptsAndAuditEvents() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.write { database in
            try seedAccount(database)
            try makeOutboxRecord(opId: "op-cascade", idempotencyKey: "idem-cascade").insert(database)
            try ActionAttemptRecord(
                opId: "op-cascade",
                attemptNumber: 1,
                status: "failed",
                startedAt: 10,
                completedAt: 11,
                retryable: 1,
                errorCode: "networkUnavailable",
                errorMessage: "retryable transport failure"
            ).insert(database)
            try ActionAuditEventRecord(
                eventId: "event-cascade",
                opId: "op-cascade",
                eventKind: "executionFailed",
                actorKind: "executor",
                occurredAt: 11,
                metadataJSON: #"{"failure":"networkUnavailable"}"#
            ).insert(database)

            #expect(try ActionOutboxRecord.fetchCount(database) == 1)
            #expect(try ActionAttemptRecord.fetchCount(database) == 1)
            #expect(try ActionAuditEventRecord.fetchCount(database) == 1)

            try AccountRecord.deleteOne(database, key: "account-1")

            #expect(try ActionOutboxRecord.fetchCount(database) == 0)
            #expect(try ActionAttemptRecord.fetchCount(database) == 0)
            #expect(try ActionAuditEventRecord.fetchCount(database) == 0)
        }
    }
}

private func seedAccount(_ database: Database) throws {
    try AccountRecord(
        id: "account-1",
        email: "user@example.test",
        displayName: "Example User",
        createdAt: 1
    ).insert(database)
}

private func makeOutboxRecord(opId: String, idempotencyKey: String) -> ActionOutboxRecord {
    ActionOutboxRecord(
        opId: opId,
        accountId: "account-1",
        targetKind: "thread",
        threadId: "thread-1",
        actionKind: "archiveThread",
        actionSchemaVersion: 1,
        idempotencyKey: idempotencyKey,
        approvalRequirement: "notRequired",
        approvalState: "notRequired",
        status: "ready",
        payloadJSON: #"{"schemaVersion":1,"body":{"reason":"userAction"}}"#,
        createdAt: 10,
        updatedAt: 10
    )
}

private func actionTableColumns(_ table: String, _ database: Database) throws -> Set<String> {
    try Set(
        Row.fetchAll(database, sql: "PRAGMA table_info(\(table.actionSQLIdentifier))")
            .compactMap { $0["name"] as String? }
    )
}

private extension String {
    var actionSQLIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
