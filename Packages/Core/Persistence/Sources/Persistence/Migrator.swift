import GRDB

enum Migrator {
    static func migrate(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
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
