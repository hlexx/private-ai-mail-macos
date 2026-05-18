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

enum M007_AttachmentCID {
    static func migrate(_ db: Database) throws {
        try db.alter(table: "attachment") { t in
            t.add(column: "content_id", .text)
            t.add(column: "data_base64", .text)
        }
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
