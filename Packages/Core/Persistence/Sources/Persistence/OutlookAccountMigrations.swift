import GRDB

enum M015_OutlookAccountAndGraphDelta {
    static func migrate(_ db: Database) throws {
        try rebuildAccountTableIfNeeded(db)
        try createGraphDeltaCheckpoint(db)
    }

    private static func rebuildAccountTableIfNeeded(_ db: Database) throws {
        let createSQL = try String.fetchOne(
            db,
            sql: """
                SELECT sql FROM sqlite_master
                WHERE type = 'table' AND name = 'account'
                """
        ) ?? ""
        guard !createSQL.contains("'outlook'") else { return }

        try db.execute(sql: "DROP TABLE IF EXISTS account_m015")
        try db.execute(sql: """
            CREATE TABLE account_m015 (
                id TEXT PRIMARY KEY NOT NULL,
                provider TEXT NOT NULL CHECK (provider IN ('gmail', 'outlook')),
                email TEXT NOT NULL,
                display_name TEXT,
                created_at INTEGER NOT NULL,
                last_synced_at INTEGER,
                UNIQUE (provider, email)
            )
            """)
        try db.execute(sql: """
            INSERT INTO account_m015 (
                id,
                provider,
                email,
                display_name,
                created_at,
                last_synced_at
            )
            SELECT
                id,
                provider,
                email,
                display_name,
                created_at,
                last_synced_at
            FROM account
            """)
        try db.drop(table: "account")
        try db.rename(table: "account_m015", to: "account")
    }

    private static func createGraphDeltaCheckpoint(_ db: Database) throws {
        try db.create(table: "graph_delta_checkpoint", ifNotExists: true) { t in
            t.column("account_id", .text)
                .notNull()
                .references("account", onDelete: .cascade)
            t.column("folder_id", .text).notNull()
            t.column("delta_url", .text).notNull()
            t.column("updated_at", .integer).notNull()
            t.primaryKey(["account_id", "folder_id"])
        }
        try db.create(
            index: "idx_graph_delta_checkpoint_account",
            on: "graph_delta_checkpoint",
            columns: ["account_id"],
            ifNotExists: true
        )
    }
}
