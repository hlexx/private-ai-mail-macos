import GRDB

enum M020_ActionOutbox {
    static func migrate(_ db: Database) throws {
        try createOutboxTable(db)
        try createAttemptTable(db)
        try createAuditEventTable(db)
    }

    private static func createOutboxTable(_ db: Database) throws {
        try db.create(table: "action_outbox") { t in
            t.primaryKey("op_id", .text)
            t.column("account_id", .text).notNull()
                .references("account", onDelete: .cascade)
            t.column("target_kind", .text).notNull()
            t.column("thread_id", .text)
            t.column("message_id", .text)
            t.column("attachment_id", .text)
            t.column("destination_kind", .text)
            t.column("destination_id", .text)
            t.column("action_kind", .text).notNull()
            t.column("action_schema_version", .integer).notNull()
            t.column("idempotency_key", .text).notNull()
            t.column("approval_requirement", .text).notNull()
            t.column("approval_state", .text).notNull()
            t.column("status", .text).notNull()
            t.column("payload_json", .text).notNull()
            t.column("result_json", .text)
            t.column("external_result_id", .text)
            t.column("last_error_kind", .text)
            t.column("last_error_code", .text)
            t.column("attempt_count", .integer).notNull().defaults(to: 0)
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.column("approved_at", .integer)
            t.column("completed_at", .integer)
        }

        try db.create(
            index: "idx_action_outbox_account_status",
            on: "action_outbox",
            columns: ["account_id", "status"]
        )
        try db.create(
            index: "idx_action_outbox_idempotency_key",
            on: "action_outbox",
            columns: ["idempotency_key"],
            unique: true
        )
        try db.create(
            index: "idx_action_outbox_target",
            on: "action_outbox",
            columns: [
                "account_id", "target_kind", "thread_id", "message_id",
                "attachment_id", "destination_kind", "destination_id",
            ]
        )
        try db.create(
            index: "idx_action_outbox_updated_at",
            on: "action_outbox",
            columns: ["updated_at"]
        )
    }

    private static func createAttemptTable(_ db: Database) throws {
        try db.create(table: "action_attempt") { t in
            t.column("op_id", .text).notNull()
            t.column("attempt_number", .integer).notNull()
            t.column("status", .text).notNull()
            t.column("started_at", .integer).notNull()
            t.column("completed_at", .integer)
            t.column("retryable", .integer).notNull().defaults(to: 0)
            t.column("error_code", .text)
            t.column("error_message", .text)
            t.primaryKey(["op_id", "attempt_number"])
            t.foreignKey(["op_id"], references: "action_outbox", onDelete: .cascade)
        }

        try db.create(
            index: "idx_action_attempt_order",
            on: "action_attempt",
            columns: ["op_id", "attempt_number"]
        )
    }

    private static func createAuditEventTable(_ db: Database) throws {
        try db.create(table: "action_audit_event") { t in
            t.primaryKey("event_id", .text)
            t.column("op_id", .text).notNull()
            t.column("event_kind", .text).notNull()
            t.column("actor_kind", .text).notNull()
            t.column("occurred_at", .integer).notNull()
            t.column("metadata_json", .text).notNull().defaults(to: "{}")
            t.foreignKey(["op_id"], references: "action_outbox", onDelete: .cascade)
        }

        try db.create(
            index: "idx_action_audit_event_order",
            on: "action_audit_event",
            columns: ["op_id", "occurred_at"]
        )
    }
}

enum M021_ActionOutboxSensitivity {
    static func migrate(_ db: Database) throws {
        try db.alter(table: "action_outbox") { t in
            t.add(column: "sensitivity", .text).notNull().defaults(to: "standard")
        }
    }
}
