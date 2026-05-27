import GRDB

enum M011_AttachmentDataPlane {
    static func migrate(_ db: Database) throws {
        try createExtractionTable(db)
        try createChunkTable(db)
        try createArtifactTable(db)
        try createProcessingJobTable(db)
    }

    private static func createExtractionTable(_ db: Database) throws {
        try db.create(table: "attachment_extraction", ifNotExists: true) { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .text).notNull()
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
    }

    private static func createChunkTable(_ db: Database) throws {
        try db.create(table: "attachment_chunk", ifNotExists: true) { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .text).notNull()
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
    }

    private static func createArtifactTable(_ db: Database) throws {
        try db.create(table: "attachment_ai_artifact", ifNotExists: true) { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .text).notNull()
            t.column("artifact_kind", .text).notNull()
            t.column("artifact_version", .integer).notNull()
            t.column("model_id", .text)
            t.column("content_hash", .text)
            t.column("payload_json", .text).notNull()
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.primaryKey([
                "account_id", "message_id", "attachment_id",
                "extraction_version", "artifact_kind", "artifact_version",
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
    }

    private static func createProcessingJobTable(_ db: Database) throws {
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
        try db.create(index: "idx_attachment_processing_job_status", on: "attachment_processing_job",
                      columns: ["status", "available_at"], ifNotExists: true)
        try db.create(index: "idx_attachment_processing_job_attachment", on: "attachment_processing_job",
                      columns: ["account_id", "message_id", "attachment_id"], ifNotExists: true)
    }
}

enum M012_AttachmentBlobStore {
    static func migrate(_ db: Database) throws {
        try createBlobTable(db)
        try addCompatibilityColumns(db)
        try db.create(
            index: "idx_attachment_ai_artifact_lookup",
            on: "attachment_ai_artifact",
            columns: ["account_id", "message_id", "attachment_id"],
            ifNotExists: true
        )
    }

    private static func createBlobTable(_ db: Database) throws {
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
    }

    private static func addCompatibilityColumns(_ db: Database) throws {
        let columns = [
            ("attachment_extraction", "content_hash", "TEXT"),
            ("attachment_extraction", "filename", "TEXT"),
            ("attachment_extraction", "byte_count", "INTEGER"),
            ("attachment_extraction", "created_at", "INTEGER NOT NULL DEFAULT 0"),
            ("attachment_extraction", "updated_at", "INTEGER NOT NULL DEFAULT 0"),
            ("attachment_extraction", "completed_at", "INTEGER"),
            ("attachment_extraction", "error_code", "TEXT"),
            ("attachment_extraction", "error_message", "TEXT"),
            ("attachment_chunk", "content_text", "TEXT"),
            ("attachment_chunk", "source_reference", "TEXT"),
            ("attachment_chunk", "page_number", "INTEGER"),
            ("attachment_chunk", "source_start", "INTEGER"),
            ("attachment_chunk", "source_end", "INTEGER"),
            ("attachment_chunk", "token_count", "INTEGER"),
            ("attachment_chunk", "created_at", "INTEGER NOT NULL DEFAULT 0"),
            ("attachment_ai_artifact", "artifact_kind", "TEXT NOT NULL DEFAULT 'attachmentSummary'"),
            ("attachment_ai_artifact", "artifact_version", "INTEGER NOT NULL DEFAULT 1"),
            ("attachment_ai_artifact", "content_hash", "TEXT"),
            ("attachment_ai_artifact", "payload_json", "TEXT"),
            ("attachment_ai_artifact", "created_at", "INTEGER NOT NULL DEFAULT 0"),
            ("attachment_ai_artifact", "updated_at", "INTEGER NOT NULL DEFAULT 0"),
        ]
        for (table, column, definition) in columns {
            try addColumnIfMissing(db, table: table, column: column, definition: definition)
        }
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

enum M014_AttachmentExtractionVersionText {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
        try rebuildIfNeeded("attachment_chunk", db: db)
        try rebuildIfNeeded("attachment_ai_artifact", db: db)
        try rebuildIfNeeded("attachment_extraction", db: db)
        try db.execute(sql: "PRAGMA foreign_key_check")
    }

    private static func rebuildIfNeeded(_ table: String, db: Database) throws {
        let columns = try tableInfo(table, db: db)
        guard let extractionVersion = columns.first(where: { $0.name == "extraction_version" }) else {
            return
        }
        guard extractionVersion.type.uppercased() != "TEXT" else {
            return
        }

        let indexes = try String.fetchAll(
            db,
            sql: """
                SELECT sql FROM sqlite_master
                WHERE type = 'index'
                  AND tbl_name = ?
                  AND sql IS NOT NULL
                ORDER BY name
                """,
            arguments: [table]
        )
        let temporaryTable = "\(table)__m014"
        try db.execute(sql: "DROP TABLE IF EXISTS \(temporaryTable.sqlIdentifier)")
        try db.execute(sql: createTableSQL(table: temporaryTable, from: columns, originalTable: table))

        let columnList = columns.map { $0.name.sqlIdentifier }.joined(separator: ", ")
        try db.execute(
            sql: """
                INSERT INTO \(temporaryTable.sqlIdentifier) (\(columnList))
                SELECT \(columnList) FROM \(table.sqlIdentifier)
                """
        )
        try db.drop(table: table)
        try db.rename(table: temporaryTable, to: table)
        for index in indexes {
            try db.execute(sql: index)
        }
    }

    private struct TableColumn {
        let name: String
        let type: String
        let notNull: Bool
        let defaultValue: String?
        let primaryKeyRank: Int
    }

    private static func tableInfo(_ table: String, db: Database) throws -> [TableColumn] {
        try Row.fetchAll(db, sql: "PRAGMA table_info(\(table.sqlIdentifier))").map { row in
            TableColumn(
                name: row["name"],
                type: row["type"] ?? "",
                notNull: (row["notnull"] as Int? ?? 0) != 0,
                defaultValue: row["dflt_value"],
                primaryKeyRank: row["pk"] ?? 0
            )
        }
    }

    private static func createTableSQL(
        table: String,
        from columns: [TableColumn],
        originalTable: String
    ) -> String {
        var definitions = columns.map { columnDefinition($0) }

        let primaryKeyColumns = columns
            .filter { $0.primaryKeyRank > 0 }
            .sorted { $0.primaryKeyRank < $1.primaryKeyRank }
            .map { $0.name.sqlIdentifier }
        if !primaryKeyColumns.isEmpty {
            definitions.append("PRIMARY KEY (\(primaryKeyColumns.joined(separator: ", ")))")
        }

        definitions.append(contentsOf: foreignKeys(for: originalTable))

        return """
            CREATE TABLE \(table.sqlIdentifier) (
                \(definitions.joined(separator: ",\n    "))
            )
            """
    }

    private static func columnDefinition(_ column: TableColumn) -> String {
        var parts = [column.name.sqlIdentifier]
        let type = column.name == "extraction_version" ? "TEXT" : normalizedType(column.type)
        if !type.isEmpty {
            parts.append(type)
        }
        if column.notNull {
            parts.append("NOT NULL")
        }
        if let defaultValue = column.defaultValue {
            parts.append("DEFAULT \(defaultValue)")
        }
        return parts.joined(separator: " ")
    }

    private static func normalizedType(_ type: String) -> String {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "BLOB" : trimmed
    }

    private static func foreignKeys(for table: String) -> [String] {
        switch table {
        case "attachment_extraction":
            return [
                """
                FOREIGN KEY (account_id, message_id, attachment_id)
                REFERENCES attachment(account_id, message_id, id)
                ON DELETE CASCADE
                """,
            ]
        case "attachment_chunk", "attachment_ai_artifact":
            return [
                """
                FOREIGN KEY (account_id, message_id, attachment_id, extraction_version)
                REFERENCES attachment_extraction(account_id, message_id, attachment_id, extraction_version)
                ON DELETE CASCADE
                """,
            ]
        default:
            return []
        }
    }
}

private extension String {
    var sqlIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
