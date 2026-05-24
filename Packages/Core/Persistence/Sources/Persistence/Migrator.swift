import Foundation
import GRDB

enum Migrator {
    static func migrate(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        migrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        migrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        migrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        migrator.registerMigration("M005_ThreadLabelAccountId", migrate: M005_ThreadLabelAccountId.migrate)
        migrator.registerMigration("M006_ThreadBrief", migrate: M006_ThreadBrief.migrate)
        migrator.registerMigration("M007_AttachmentCID", migrate: M007_AttachmentCID.migrate)
        migrator.registerMigration("M008_BackfillInboxLabel", migrate: M008_BackfillInboxLabel.migrate)
        migrator.registerMigration("M009_BackfillInboxLabelV2", migrate: M009_BackfillInboxLabelV2.migrate)
        migrator.registerMigration("M010_SignalLabelReconcile", migrate: M010_SignalLabelReconcile.migrate)
        migrator.registerMigration("M011_AttachmentDataPlane", migrate: M011_AttachmentDataPlane.migrate)
        migrator.registerMigration("M012_AttachmentBlobStore", migrate: M012_AttachmentBlobStore.migrate)
        try migrator.migrate(db)
    }
}

enum M001_InitialSchema {
    static func migrate(_ db: Database) throws {
        try db.create(table: "account") { t in
            t.primaryKey("id", .text)
            t.column("provider", .text).notNull().check { $0 == "gmail" }
            t.column("email", .text).notNull()
            t.column("display_name", .text)
            t.column("created_at", .integer).notNull()
            t.column("last_synced_at", .integer)
            t.uniqueKey(["provider", "email"])
        }

        try db.create(table: "sync_state") { t in
            t.primaryKey("account_id", .text)
                .references("account", onDelete: .cascade)
            t.column("history_id", .text)
            t.column("last_bootstrap_at", .integer)
            t.column("status", .text).notNull().defaults(to: "idle")
        }

        try db.create(table: "thread") { t in
            t.column("id", .text).notNull()
            t.column("account_id", .text).notNull()
                .references("account", onDelete: .cascade)
            t.column("subject", .text)
            t.column("snippet", .text)
            t.column("last_message_at", .integer).notNull()
            t.column("message_count", .integer).notNull().defaults(to: 0)
            t.column("has_unread", .integer).notNull().defaults(to: 0)
            t.primaryKey(["account_id", "id"])
        }
        try db.create(
            index: "idx_thread_last_message",
            on: "thread",
            columns: ["account_id", "last_message_at"]
        )

        try db.create(table: "message") { t in
            t.column("id", .text).notNull()
            t.column("thread_id", .text).notNull()
            t.column("account_id", .text).notNull()
                .references("account", onDelete: .cascade)
            t.column("message_id_header", .text)
            t.column("from_addr", .text)
            t.column("to_addr", .text)
            t.column("cc_addr", .text)
            t.column("sent_at", .integer).notNull()
            t.column("snippet", .text)
            t.column("body_html", .text)
            t.column("body_text", .text)
            t.column("flags", .integer).notNull().defaults(to: 0)
            t.primaryKey(["account_id", "id"])
        }
        try db.create(
            index: "idx_message_thread",
            on: "message",
            columns: ["account_id", "thread_id", "sent_at"]
        )

        try db.create(table: "attachment") { t in
            t.column("id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("account_id", .text).notNull()
                .references("account", onDelete: .cascade)
            t.column("filename", .text)
            t.column("mime", .text)
            t.column("size_bytes", .integer)
            t.primaryKey(["account_id", "message_id", "id"])
            t.foreignKey(["account_id", "message_id"], references: "message", columns: ["account_id", "id"], onDelete: .cascade)
        }
    }
}

enum M002_Labels {
    static func migrate(_ db: Database) throws {
        try db.create(table: "label") { t in
            t.column("id", .text).notNull()
            t.column("account_id", .text).notNull()
                .references("account", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("type", .text).notNull()
            t.column("color", .text)
            t.column("messages_unread_count", .integer).notNull().defaults(to: 0)
            t.column("messages_total_count", .integer).notNull().defaults(to: 0)
            t.primaryKey(["account_id", "id"])
        }

        try db.create(table: "thread_label") { t in
            t.column("thread_id", .text).notNull()
            t.column("label_id", .text).notNull()
            t.primaryKey(["thread_id", "label_id"])
        }

        try db.create(
            index: "idx_thread_label_label",
            on: "thread_label",
            columns: ["label_id"]
        )
        try db.create(
            index: "idx_thread_label_thread",
            on: "thread_label",
            columns: ["thread_id"]
        )
    }
}

enum M003_TrustedSender {
    static func migrate(_ db: Database) throws {
        try db.create(table: "trusted_sender") { t in
            t.column("account_id", .text).notNull()
                .references("account", onDelete: .cascade)
            t.column("from_addr", .text).notNull()
            t.primaryKey(["account_id", "from_addr"])
        }
    }
}

enum M004_TranslatedText {
    static func migrate(_ db: Database) throws {
        try db.alter(table: "message") { t in
            t.add(column: "translated_text", .text)
        }
    }
}

enum M005_ThreadLabelAccountId {
    static func migrate(_ db: Database) throws {
        // Preserve existing thread-label data by migrating through a temp table
        try db.execute(sql: """
            CREATE TABLE thread_label_new (
                account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
                thread_id TEXT NOT NULL,
                label_id TEXT NOT NULL,
                PRIMARY KEY (account_id, thread_id, label_id)
            )
            """)
        // Migrate existing rows, deriving account_id from thread.
        // Gmail thread IDs are globally unique, so thread alone suffices.
        // No label join — orphaned thread_label rows (label deleted before
        // migration) must be preserved; they are cleaned on next sync.
        try db.execute(sql: """
            INSERT OR IGNORE INTO thread_label_new (account_id, thread_id, label_id)
            SELECT t.account_id, tl.thread_id, tl.label_id
            FROM thread_label tl
            JOIN thread t ON t.id = tl.thread_id
            """)
        try db.drop(table: "thread_label")
        try db.rename(table: "thread_label_new", to: "thread_label")
        try db.create(
            index: "idx_thread_label_label",
            on: "thread_label",
            columns: ["account_id", "label_id"]
        )
        try db.create(
            index: "idx_thread_label_thread",
            on: "thread_label",
            columns: ["account_id", "thread_id"]
        )
    }
}

enum M006_ThreadBrief {
    static func migrate(_ db: Database) throws {
        try db.create(table: "thread_brief") { t in
            t.column("account_id", .text).notNull()
                .references("account", onDelete: .cascade)
            t.column("thread_id", .text).notNull()
            t.column("latest_message_id", .text).notNull()
            t.column("summary", .text)
            t.column("request", .text)
            t.column("deadline", .text)
            t.column("risk", .text)
            t.column("next_step", .text)
            t.column("confidence", .double).notNull().defaults(to: 0)
            t.column("evidence_json", .text).notNull().defaults(to: "[]")
            t.column("language", .text)
            t.column("generated_at", .integer).notNull()
            t.primaryKey(["account_id", "thread_id"])
            t.foreignKey(
                ["account_id", "thread_id"],
                references: "thread",
                columns: ["account_id", "id"],
                onDelete: .cascade
            )
        }
        try db.create(
            index: "idx_thread_brief_account",
            on: "thread_brief",
            columns: ["account_id"]
        )
        try db.create(
            index: "idx_thread_brief_request",
            on: "thread_brief",
            columns: ["account_id", "request"]
        )
        try db.create(
            index: "idx_thread_brief_deadline",
            on: "thread_brief",
            columns: ["account_id", "deadline"]
        )
    }
}

enum M007_AttachmentCID {
    static func migrate(_ db: Database) throws {
        try db.alter(table: "attachment") { t in
            t.add(column: "content_id", .text)
            t.add(column: "data_base64", .text)
        }
    }
}

/// Backfill `INBOX` label for threads that were synced before label-aware
/// code landed (v0.1.4 and earlier). Symptom: after upgrading to 0.1.6
/// the sidebar's `All Accounts` / `Inbox` / `Sent` / `Starred` filters
/// all return empty because their SQL requires a matching row in
/// `thread_label`, and old threads never got those rows populated.
/// Treat any thread with **zero** thread_label rows as if it had been
/// observed with the `INBOX` label — that matches where the user
/// previously saw it.
///
/// Idempotent: re-runs find no zero-label threads and do nothing.
/// Future syncs overwrite this backfill the moment Gmail's labelIds
/// arrive for that thread.
enum M008_BackfillInboxLabel {
    static func migrate(_ db: Database) throws {
        // Ensure the canonical INBOX label row exists per account before
        // referencing it from thread_label (FK constraint).
        try db.execute(sql: """
            INSERT OR IGNORE INTO label (id, account_id, name, type, color, messages_unread_count, messages_total_count)
            SELECT 'INBOX', a.id, 'Inbox', 'system', NULL, 0, 0
            FROM account a
            """)

        // Insert (account_id, thread_id, 'INBOX') for every thread that
        // currently has no thread_label rows at all.
        try db.execute(sql: """
            INSERT OR IGNORE INTO thread_label (account_id, thread_id, label_id)
            SELECT t.account_id, t.id, 'INBOX'
            FROM thread t
            WHERE NOT EXISTS (
                SELECT 1 FROM thread_label tl
                WHERE tl.account_id = t.account_id AND tl.thread_id = t.id
            )
            """)
    }
}

/// Broader INBOX backfill: M008 only caught threads with **zero** label rows.
/// Many legacy threads have UNREAD / CATEGORY_PROMOTIONS / IMPORTANT but never
/// got an INBOX row. M009 inserts INBOX for any thread that:
/// - does NOT already have INBOX
/// - does NOT have TRASH, SPAM, or DRAFT (explicitly out-of-inbox)
/// - is NOT sent-only (has SENT but no other non-meta labels)
/// Idempotent: INSERT OR IGNORE prevents duplicates on re-run.
enum M009_BackfillInboxLabelV2 {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO label (id, account_id, name, type, color, messages_unread_count, messages_total_count)
            SELECT 'INBOX', a.id, 'Inbox', 'system', NULL, 0, 0
            FROM account a
            """)

        try db.execute(sql: """
            INSERT OR IGNORE INTO thread_label (account_id, thread_id, label_id)
            SELECT t.account_id, t.id, 'INBOX'
            FROM thread t
            WHERE NOT EXISTS (
                SELECT 1 FROM thread_label tl_in
                WHERE tl_in.account_id = t.account_id
                  AND tl_in.thread_id = t.id
                  AND tl_in.label_id = 'INBOX'
            )
            AND NOT EXISTS (
                SELECT 1 FROM thread_label tl_out
                WHERE tl_out.account_id = t.account_id
                  AND tl_out.thread_id = t.id
                  AND tl_out.label_id IN ('TRASH','SPAM','DRAFT')
            )
            AND NOT (
                EXISTS (SELECT 1 FROM thread_label tl_sent
                        WHERE tl_sent.account_id = t.account_id
                          AND tl_sent.thread_id = t.id
                          AND tl_sent.label_id = 'SENT')
                AND NOT EXISTS (SELECT 1 FROM thread_label tl_any
                                WHERE tl_any.account_id = t.account_id
                                  AND tl_any.thread_id = t.id
                                  AND tl_any.label_id NOT IN ('SENT','UNREAD','IMPORTANT'))
            )
            """)
    }
}

/// Signal to the app that a one-shot label reconciliation pass is
/// needed on next launch. Does NOT modify schema or data — just flips
/// the `pam.needsLabelReconcile` flag in UserDefaults so the running
/// app picks it up post-launch and calls `LabelReconciler.reconcileInbox`
/// per account.
///
/// The reason this migration is necessary: M008 + M009 (v0.1.7/v0.1.8)
/// were too eager — they inferred `INBOX` for any thread that didn't
/// explicitly carry `TRASH/SPAM/DRAFT`. Archived threads in Gmail look
/// the same as "should-be-inbox" from that local view, so the backfill
/// flooded Inbox with archived mail. This migration kicks off the
/// authoritative re-check against `users.messages.list?q=label:INBOX`.
enum M010_SignalLabelReconcile {
    static func migrate(_ db: Database) throws {
        UserDefaults.standard.set(true, forKey: "pam.needsLabelReconcile")
    }
}

enum M011_AttachmentDataPlane {
    static func migrate(_ db: Database) throws {
        try db.create(table: "attachment_extraction", ifNotExists: true) { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .integer).notNull()
            t.column("status", .text).notNull()
            t.column("content_hash", .text)
            t.column("mime", .text)
            t.column("filename", .text)
            t.column("byte_count", .integer)
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.column("completed_at", .integer)
            t.column("error_code", .text)
            t.column("error_message", .text)
            t.primaryKey(["account_id", "message_id", "attachment_id", "extraction_version"])
            t.foreignKey(
                ["account_id", "message_id", "attachment_id"],
                references: "attachment",
                columns: ["account_id", "message_id", "id"],
                onDelete: .cascade
            )
        }
        try db.create(
            index: "idx_attachment_extraction_attachment",
            on: "attachment_extraction",
            columns: ["account_id", "message_id", "attachment_id"],
            ifNotExists: true
        )

        try db.create(table: "attachment_chunk", ifNotExists: true) { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .integer).notNull()
            t.column("chunk_index", .integer).notNull()
            t.column("content_text", .text).notNull()
            t.column("source_reference", .text)
            t.column("page_number", .integer)
            t.column("source_start", .integer)
            t.column("source_end", .integer)
            t.column("token_count", .integer)
            t.column("created_at", .integer).notNull()
            t.primaryKey(["account_id", "message_id", "attachment_id", "extraction_version", "chunk_index"])
            t.foreignKey(
                ["account_id", "message_id", "attachment_id", "extraction_version"],
                references: "attachment_extraction",
                columns: ["account_id", "message_id", "attachment_id", "extraction_version"],
                onDelete: .cascade
            )
        }
        try db.create(
            index: "idx_attachment_chunk_attachment",
            on: "attachment_chunk",
            columns: ["account_id", "message_id", "attachment_id", "extraction_version"],
            ifNotExists: true
        )

        try db.create(table: "attachment_ai_artifact", ifNotExists: true) { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .integer).notNull()
            t.column("artifact_kind", .text).notNull()
            t.column("artifact_version", .integer).notNull()
            t.column("model_id", .text)
            t.column("content_hash", .text)
            t.column("payload_json", .text).notNull()
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.primaryKey([
                "account_id",
                "message_id",
                "attachment_id",
                "extraction_version",
                "artifact_kind",
                "artifact_version",
            ])
            t.foreignKey(
                ["account_id", "message_id", "attachment_id", "extraction_version"],
                references: "attachment_extraction",
                columns: ["account_id", "message_id", "attachment_id", "extraction_version"],
                onDelete: .cascade
            )
        }
        try db.create(
            index: "idx_attachment_ai_artifact_attachment",
            on: "attachment_ai_artifact",
            columns: ["account_id", "message_id", "attachment_id", "extraction_version"],
            ifNotExists: true
        )

        try db.create(table: "attachment_processing_job", ifNotExists: true) { t in
            t.primaryKey("id", .text)
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("job_kind", .text).notNull()
            t.column("status", .text).notNull()
            t.column("priority", .integer).notNull().defaults(to: 0)
            t.column("attempt_count", .integer).notNull().defaults(to: 0)
            t.column("available_at", .integer).notNull()
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.column("last_error_code", .text)
            t.column("last_error_message", .text)
            t.foreignKey(
                ["account_id", "message_id", "attachment_id"],
                references: "attachment",
                columns: ["account_id", "message_id", "id"],
                onDelete: .cascade
            )
        }
        try db.create(
            index: "idx_attachment_processing_job_status",
            on: "attachment_processing_job",
            columns: ["status", "available_at"],
            ifNotExists: true
        )
        try db.create(
            index: "idx_attachment_processing_job_attachment",
            on: "attachment_processing_job",
            columns: ["account_id", "message_id", "attachment_id"],
            ifNotExists: true
        )
    }
}

enum M012_AttachmentBlobStore {
    static func migrate(_ db: Database) throws {
        try db.create(table: "attachment_blob", ifNotExists: true) { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("relative_path", .text).notNull()
            t.column("byte_count", .integer).notNull()
            t.column("sha256", .text).notNull()
            t.column("stored_at", .integer).notNull()
            t.primaryKey(["account_id", "message_id", "attachment_id"])
            t.foreignKey(
                ["account_id", "message_id", "attachment_id"],
                references: "attachment",
                columns: ["account_id", "message_id", "id"],
                onDelete: .cascade
            )
        }

        try addColumnIfMissing(db, table: "attachment_extraction", column: "content_hash", definition: "TEXT")
        try addColumnIfMissing(db, table: "attachment_extraction", column: "filename", definition: "TEXT")
        try addColumnIfMissing(db, table: "attachment_extraction", column: "byte_count", definition: "INTEGER")
        try addColumnIfMissing(db, table: "attachment_extraction", column: "created_at", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "attachment_extraction", column: "updated_at", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "attachment_extraction", column: "completed_at", definition: "INTEGER")
        try addColumnIfMissing(db, table: "attachment_extraction", column: "error_code", definition: "TEXT")
        try addColumnIfMissing(db, table: "attachment_extraction", column: "error_message", definition: "TEXT")

        try addColumnIfMissing(db, table: "attachment_chunk", column: "content_text", definition: "TEXT")
        try addColumnIfMissing(db, table: "attachment_chunk", column: "source_reference", definition: "TEXT")
        try addColumnIfMissing(db, table: "attachment_chunk", column: "page_number", definition: "INTEGER")
        try addColumnIfMissing(db, table: "attachment_chunk", column: "source_start", definition: "INTEGER")
        try addColumnIfMissing(db, table: "attachment_chunk", column: "source_end", definition: "INTEGER")
        try addColumnIfMissing(db, table: "attachment_chunk", column: "token_count", definition: "INTEGER")
        try addColumnIfMissing(db, table: "attachment_chunk", column: "created_at", definition: "INTEGER NOT NULL DEFAULT 0")

        try addColumnIfMissing(db, table: "attachment_ai_artifact", column: "artifact_kind", definition: "TEXT NOT NULL DEFAULT 'attachmentSummary'")
        try addColumnIfMissing(db, table: "attachment_ai_artifact", column: "artifact_version", definition: "INTEGER NOT NULL DEFAULT 1")
        try addColumnIfMissing(db, table: "attachment_ai_artifact", column: "content_hash", definition: "TEXT")
        try addColumnIfMissing(db, table: "attachment_ai_artifact", column: "payload_json", definition: "TEXT")
        try addColumnIfMissing(db, table: "attachment_ai_artifact", column: "created_at", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "attachment_ai_artifact", column: "updated_at", definition: "INTEGER NOT NULL DEFAULT 0")
        try db.create(
            index: "idx_attachment_ai_artifact_lookup",
            on: "attachment_ai_artifact",
            columns: ["account_id", "message_id", "attachment_id"],
            ifNotExists: true
        )
    }

    private static func addColumnIfMissing(
        _ db: Database,
        table: String,
        column: String,
        definition: String
    ) throws {
        let existing = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table.sqlIdentifier))")
            .compactMap { $0["name"] as String? }
        guard !existing.contains(column) else { return }
        try db.execute(sql: "ALTER TABLE \(table.sqlIdentifier) ADD COLUMN \(column.sqlIdentifier) \(definition)")
    }
}

private extension String {
    var sqlIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
