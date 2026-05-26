import GRDB
import Testing
@testable import Persistence

@Suite("Attachment AI Artifact Migration")
struct AttachmentArtifactMigrationTests {
    @Test func freshMigrationCreatesTextExtractionVersionColumns() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.read { database in
            let columnTypes = try extractionVersionColumnTypes(database)

            #expect(columnTypes["attachment_extraction"] == "TEXT")
            #expect(columnTypes["attachment_chunk"] == "TEXT")
            #expect(columnTypes["attachment_ai_artifact"] == "TEXT")
        }
    }

    @Test func migrationCreatesAttachmentArtifactTablesAndCascades() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.write { database in
            try AccountRecord(id: "a1", email: "a@example.com", createdAt: 1).insert(database)
            try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 1).insert(database)
            try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 1).insert(database)
            try AttachmentRecord(
                id: "att1",
                messageId: "m1",
                accountId: "a1",
                filename: "invoice.txt",
                mime: "text/plain",
                sizeBytes: 32
            ).insert(database)

            try AttachmentBlobRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                relativePath: "a1/m1/att1",
                byteCount: 32,
                sha256: "abc",
                storedAt: 1
            ).insert(database)

            try AttachmentExtractionRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: "v1",
                status: "extracted",
                contentHash: "abc",
                mime: "text/plain",
                filename: "invoice.txt",
                byteCount: 32,
                createdAt: 2,
                updatedAt: 2,
                completedAt: 2,
                errorCode: nil,
                errorMessage: nil
            ).insert(database)

            try AttachmentChunkRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: "v1",
                chunkIndex: 0,
                contentText: "Amount due",
                sourceStart: 0,
                sourceEnd: 10,
                tokenCount: 2,
                createdAt: 2
            ).insert(database)

            try AttachmentAIArtifactRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: "v1",
                artifactKind: "attachmentSummary:attachment-summary.v1:attachment-summary.schema.v1",
                artifactVersion: 1,
                modelId: "local",
                contentHash: "abc",
                payloadJSON: "{}",
                createdAt: 3,
                updatedAt: 3
            ).insert(database)

            #expect(try AttachmentAIArtifactRecord.fetchCount(database) == 1)
            try AccountRecord.deleteOne(database, key: "a1")
            #expect(try AttachmentBlobRecord.fetchCount(database) == 0)
            #expect(try AttachmentExtractionRecord.fetchCount(database) == 0)
            #expect(try AttachmentChunkRecord.fetchCount(database) == 0)
            #expect(try AttachmentAIArtifactRecord.fetchCount(database) == 0)
        }
    }

    @Test func migratesDatabaseThatAlreadyAppliedAttachmentDataPlane() throws {
        let dbQueue = try DatabaseQueue(configuration: .init())

        var preMigrator = DatabaseMigrator()
        preMigrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        preMigrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        preMigrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        preMigrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        preMigrator.registerMigration("M005_ThreadLabelAccountId", migrate: M005_ThreadLabelAccountId.migrate)
        preMigrator.registerMigration("M006_ThreadBrief", migrate: M006_ThreadBrief.migrate)
        preMigrator.registerMigration("M007_AttachmentCID", migrate: M007_AttachmentCID.migrate)
        preMigrator.registerMigration("M008_BackfillInboxLabel", migrate: M008_BackfillInboxLabel.migrate)
        preMigrator.registerMigration("M009_BackfillInboxLabelV2", migrate: M009_BackfillInboxLabelV2.migrate)
        preMigrator.registerMigration("M010_SignalLabelReconcile", migrate: M010_SignalLabelReconcile.migrate)
        preMigrator.registerMigration("M011_AttachmentDataPlane", migrate: M011_AttachmentDataPlane.migrate)
        try preMigrator.migrate(dbQueue)

        try Migrator.migrate(dbQueue)

        try dbQueue.read { database in
            let migrations = try String.fetchAll(database, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
            #expect(migrations.contains("M011_AttachmentDataPlane"))
            #expect(migrations.contains("M012_AttachmentBlobStore"))
            #expect(migrations.contains("M014_AttachmentExtractionVersionText"))

            let tables = try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            #expect(tables.contains("attachment_extraction"))
            #expect(tables.contains("attachment_chunk"))
            #expect(tables.contains("attachment_ai_artifact"))
            #expect(tables.contains("attachment_processing_job"))
            #expect(tables.contains("attachment_blob"))
        }
    }

    @Test func m014RebuildsIntegerExtractionVersionTablesAndPreservesData() throws {
        let dbQueue = try DatabaseQueue(configuration: .init())

        var preMigrator = DatabaseMigrator()
        preMigrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        preMigrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        preMigrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        preMigrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        preMigrator.registerMigration("M005_ThreadLabelAccountId", migrate: M005_ThreadLabelAccountId.migrate)
        preMigrator.registerMigration("M006_ThreadBrief", migrate: M006_ThreadBrief.migrate)
        preMigrator.registerMigration("M007_AttachmentCID", migrate: M007_AttachmentCID.migrate)
        preMigrator.registerMigration("M008_BackfillInboxLabel", migrate: M008_BackfillInboxLabel.migrate)
        preMigrator.registerMigration("M009_BackfillInboxLabelV2", migrate: M009_BackfillInboxLabelV2.migrate)
        preMigrator.registerMigration("M010_SignalLabelReconcile", migrate: M010_SignalLabelReconcile.migrate)
        preMigrator.registerMigration("M011_AttachmentDataPlane", migrate: LegacyIntegerAttachmentDataPlane.migrate)
        try preMigrator.migrate(dbQueue)

        try dbQueue.write { database in
            try addLegacyCompatibilityColumns(database)
            try AccountRecord(id: "a1", email: "a@example.com", createdAt: 1).insert(database)
            try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 1).insert(database)
            try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 1).insert(database)
            try AttachmentRecord(id: "att1", messageId: "m1", accountId: "a1").insert(database)

            try database.execute(
                sql: """
                INSERT INTO attachment_extraction (
                    account_id, message_id, attachment_id, extraction_version, status,
                    content_hash, mime, filename, byte_count, created_at, updated_at,
                    completed_at, text, unsupported_reason, generated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "a1", "m1", "att1", 1, "extracted", "hash1", "text/plain", "invoice.txt",
                    42, 100, 101, 102, "legacy extracted text", nil, 103,
                ]
            )
            try database.execute(
                sql: """
                INSERT INTO attachment_chunk (
                    account_id, message_id, attachment_id, extraction_version, chunk_index,
                    content_text, source_reference, page_number, source_start, source_end,
                    token_count, created_at, text, source_offset
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "a1", "m1", "att1", 1, 0, "Amount due", "invoice.txt", 1, 4, 14,
                    2, 104, "Amount due legacy", 4,
                ]
            )
            try database.execute(
                sql: """
                INSERT INTO attachment_ai_artifact (
                    account_id, message_id, attachment_id, extraction_version, artifact_kind,
                    artifact_version, model_id, content_hash, payload_json, created_at,
                    updated_at, content_json, task_id, prompt_version, schema_version,
                    input_fingerprint, generated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "a1", "m1", "att1", 1,
                    "attachmentSummary:attachment-summary.v1:attachment-summary.schema.v1",
                    1, "local", "hash1", #"{"summary":"canonical"}"#, 105, 106,
                    #"{"summary":"legacy"}"#, "attachmentSummary", "attachment-summary.v1",
                    "attachment-summary.schema.v1", "hash1", 107,
                ]
            )
        }

        try Migrator.migrate(dbQueue)

        try dbQueue.read { database in
            let columnTypes = try extractionVersionColumnTypes(database)
            #expect(columnTypes["attachment_extraction"] == "TEXT")
            #expect(columnTypes["attachment_chunk"] == "TEXT")
            #expect(columnTypes["attachment_ai_artifact"] == "TEXT")

            #expect(try storedExtractionVersionType(database, table: "attachment_extraction") == "text")
            #expect(try storedExtractionVersionType(database, table: "attachment_chunk") == "text")
            #expect(try storedExtractionVersionType(database, table: "attachment_ai_artifact") == "text")
            #expect(try String.fetchOne(database, sql: "SELECT extraction_version FROM attachment_extraction") == "1")
            #expect(try String.fetchOne(database, sql: "SELECT text FROM attachment_extraction") == "legacy extracted text")
            #expect(try String.fetchOne(database, sql: "SELECT text FROM attachment_chunk") == "Amount due legacy")
            #expect(try Int.fetchOne(database, sql: "SELECT source_offset FROM attachment_chunk") == 4)
            #expect(try String.fetchOne(database, sql: "SELECT content_json FROM attachment_ai_artifact") == #"{"summary":"legacy"}"#)
            #expect(try String.fetchOne(database, sql: "SELECT task_id FROM attachment_ai_artifact") == "attachmentSummary")
            #expect(try String.fetchOne(database, sql: "SELECT input_fingerprint FROM attachment_ai_artifact") == "hash1")

            let extractionIndexes = try indexNames(database, table: "attachment_extraction")
            let chunkIndexes = try indexNames(database, table: "attachment_chunk")
            let artifactIndexes = try indexNames(database, table: "attachment_ai_artifact")
            #expect(extractionIndexes.contains("idx_attachment_extraction_attachment"))
            #expect(chunkIndexes.contains("idx_attachment_chunk_attachment"))
            #expect(artifactIndexes.contains("idx_attachment_ai_artifact_attachment"))
            #expect(artifactIndexes.contains("idx_attachment_ai_artifact_lookup"))
        }

        try dbQueue.write { database in
            try database.execute(
                sql: "DELETE FROM attachment WHERE account_id = ? AND message_id = ? AND id = ?",
                arguments: ["a1", "m1", "att1"]
            )
            #expect(try AttachmentExtractionRecord.fetchCount(database) == 0)
            #expect(try AttachmentChunkRecord.fetchCount(database) == 0)
            #expect(try AttachmentAIArtifactRecord.fetchCount(database) == 0)
        }
    }
}

private enum LegacyIntegerAttachmentDataPlane {
    static func migrate(_ db: Database) throws {
        try db.create(table: "attachment_extraction") { t in
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
            columns: ["account_id", "message_id", "attachment_id"]
        )

        try db.create(table: "attachment_chunk") { t in
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
            columns: ["account_id", "message_id", "attachment_id", "extraction_version"]
        )

        try db.create(table: "attachment_ai_artifact") { t in
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
            columns: ["account_id", "message_id", "attachment_id", "extraction_version"]
        )

        try db.create(table: "attachment_processing_job") { t in
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
            columns: ["status", "available_at"]
        )
        try db.create(
            index: "idx_attachment_processing_job_attachment",
            on: "attachment_processing_job",
            columns: ["account_id", "message_id", "attachment_id"]
        )
    }
}

private func addLegacyCompatibilityColumns(_ db: Database) throws {
    try db.execute(sql: "ALTER TABLE attachment_extraction ADD COLUMN text TEXT")
    try db.execute(sql: "ALTER TABLE attachment_extraction ADD COLUMN unsupported_reason TEXT")
    try db.execute(sql: "ALTER TABLE attachment_extraction ADD COLUMN generated_at INTEGER")
    try db.execute(sql: "ALTER TABLE attachment_chunk ADD COLUMN text TEXT")
    try db.execute(sql: "ALTER TABLE attachment_chunk ADD COLUMN source_offset INTEGER")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN content_json TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN task_id TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN prompt_version TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN schema_version TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN input_fingerprint TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN generated_at INTEGER")
}

private func extractionVersionColumnTypes(_ db: Database) throws -> [String: String] {
    var types: [String: String] = [:]
    for table in ["attachment_extraction", "attachment_chunk", "attachment_ai_artifact"] {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
        let type = rows.first { ($0["name"] as String?) == "extraction_version" }?["type"] as String?
        types[table] = type
    }
    return types
}

private func storedExtractionVersionType(_ db: Database, table: String) throws -> String? {
    try String.fetchOne(db, sql: "SELECT typeof(extraction_version) FROM \(table) LIMIT 1")
}

private func indexNames(_ db: Database, table: String) throws -> [String] {
    try Row.fetchAll(db, sql: "PRAGMA index_list(\(table))").compactMap { row in
        row["name"] as String?
    }
}
