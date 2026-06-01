import Foundation
import GRDB

public struct LocalDraftStore: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func save(_ draft: DraftRecord) async throws -> DraftRecord {
        try await db.write { database in
            try draft.save(database)
            return draft
        }
    }

    public func fetch(id: String) throws -> DraftRecord? {
        try db.read { database in
            try DraftRecord.fetchOne(database, key: id)
        }
    }

    public func delete(id: String) async throws {
        try await db.write { database in
            _ = try DraftRecord.deleteOne(database, key: id)
        }
    }
}

public struct LocalSendQueueStore: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func insert(_ item: SendQueueItemRecord) async throws -> SendQueueItemRecord {
        try await db.write { database in
            try item.insert(database)
            return item
        }
    }

    public func save(_ item: SendQueueItemRecord) async throws -> SendQueueItemRecord {
        try await db.write { database in
            try item.save(database)
            return item
        }
    }

    public func fetch(id: String) throws -> SendQueueItemRecord? {
        try db.read { database in
            try SendQueueItemRecord.fetchOne(database, key: id)
        }
    }

    public func fetch(provider: String, accountId: String, idempotencyKey: String) throws -> SendQueueItemRecord? {
        try db.read { database in
            try SendQueueItemRecord
                .filter(Column("provider") == provider)
                .filter(Column("account_id") == accountId)
                .filter(Column("idempotency_key") == idempotencyKey)
                .fetchOne(database)
        }
    }
}

enum M017_DraftsAndSendQueue {
    static func migrate(_ db: Database) throws {
        try createDraftTable(db)
        try createSendQueueTable(db)
    }

    private static func createDraftTable(_ db: Database) throws {
        try db.create(table: "draft") { t in
            t.primaryKey("id", .text)
            t.column("account_id", .text)
                .notNull()
                .references("account", onDelete: .cascade)
            t.column("provider", .text)
                .notNull()
                .check(sql: "provider IN ('gmail', 'outlook')")
            t.column("from_addr", .text).notNull()
            t.column("to_addr", .text).notNull()
            t.column("cc_addr", .text)
            t.column("bcc_addr", .text)
            t.column("subject", .text).notNull().defaults(to: "")
            t.column("body_text", .text)
            t.column("body_html", .text)
            t.column("body_storage", .text)
                .notNull()
                .defaults(to: "sqlite")
                .check(sql: "body_storage IN ('sqlite', 'local_file')")
            t.column("thread_id", .text)
            t.column("reply_to_provider_message_id", .text)
            t.column("rfc_message_id", .text)
            t.column("rfc_in_reply_to", .text)
            t.column("rfc_references_json", .text).notNull().defaults(to: "[]")
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
        }
        try db.create(
            index: "idx_draft_account_updated",
            on: "draft",
            columns: ["account_id", "updated_at"]
        )
        try db.create(
            index: "idx_draft_thread",
            on: "draft",
            columns: ["account_id", "thread_id"]
        )
    }

    private static func createSendQueueTable(_ db: Database) throws {
        try db.create(table: "send_queue_item") { t in
            t.primaryKey("id", .text)
            t.column("draft_id", .text)
                .references("draft", onDelete: .setNull)
            t.column("account_id", .text)
                .notNull()
                .references("account", onDelete: .cascade)
            t.column("provider", .text)
                .notNull()
                .check(sql: "provider IN ('gmail', 'outlook')")
            t.column("idempotency_key", .text).notNull()
            t.column("status", .text)
                .notNull()
                .check(sql: """
                    status IN (
                        'pending',
                        'sending',
                        'retryScheduled',
                        'needsConsent',
                        'failed',
                        'sent',
                        'canceled',
                        'duplicateSuppressed'
                    )
                    """)
            t.column("from_addr", .text).notNull()
            t.column("to_addr", .text).notNull()
            t.column("cc_addr", .text)
            t.column("bcc_addr", .text)
            t.column("subject", .text).notNull().defaults(to: "")
            t.column("body_text", .text)
            t.column("body_html", .text)
            t.column("body_storage", .text)
                .notNull()
                .defaults(to: "sqlite")
                .check(sql: "body_storage IN ('sqlite', 'local_file')")
            t.column("thread_id", .text)
            t.column("reply_to_provider_message_id", .text)
            t.column("provider_message_id", .text)
            t.column("provider_thread_id", .text)
            t.column("rfc_message_id", .text)
            t.column("rfc_in_reply_to", .text)
            t.column("rfc_references_json", .text).notNull().defaults(to: "[]")
            t.column("attempts", .integer)
                .notNull()
                .defaults(to: 0)
                .check(sql: "attempts >= 0")
            t.column("max_attempts", .integer)
                .notNull()
                .defaults(to: 5)
                .check(sql: "max_attempts >= 0")
            t.column("next_attempt_at", .integer)
            t.column("last_attempt_at", .integer)
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.column("sent_at", .integer)
            t.column("sanitized_error_category", .text)
            t.column("sanitized_error_code", .text)
            t.column("sanitized_error_message", .text)
            t.column("retry_after_seconds", .integer)
            t.uniqueKey(["provider", "account_id", "idempotency_key"])
        }

        try db.create(
            index: "idx_send_queue_account_status",
            on: "send_queue_item",
            columns: ["account_id", "status", "updated_at"]
        )
        try db.create(
            index: "idx_send_queue_eligible",
            on: "send_queue_item",
            columns: ["status", "next_attempt_at", "created_at"]
        )
    }
}
