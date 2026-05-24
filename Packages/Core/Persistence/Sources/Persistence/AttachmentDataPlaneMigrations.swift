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
    }

    private static func createChunkTable(_ db: Database) throws {
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
    }

    private static func createArtifactTable(_ db: Database) throws {
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

private extension String {
    var sqlIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
