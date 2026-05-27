import GRDB
import Testing
@testable import Persistence

@Suite("Attachment AI Artifact Migration")
struct AttachmentArtifactMigrationTests {
    @Test func freshMigrationUsesTextExtractionVersion() throws {
        let db = try AppDatabase.openInMemorySync()

        try db.dbQueue.read { database in
            let extractionType = try columnType("attachment_extraction", "extraction_version", database)
            let chunkType = try columnType("attachment_chunk", "extraction_version", database)
            let artifactType = try columnType("attachment_ai_artifact", "extraction_version", database)
            #expect(extractionType == "TEXT")
            #expect(chunkType == "TEXT")
            #expect(artifactType == "TEXT")
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

            let artifactCount = try AttachmentAIArtifactRecord.fetchCount(database)
            #expect(artifactCount == 1)
            try AccountRecord.deleteOne(database, key: "a1")
            let blobCount = try AttachmentBlobRecord.fetchCount(database)
            let extractionCount = try AttachmentExtractionRecord.fetchCount(database)
            let chunkCount = try AttachmentChunkRecord.fetchCount(database)
            let remainingArtifactCount = try AttachmentAIArtifactRecord.fetchCount(database)
            #expect(blobCount == 0)
            #expect(extractionCount == 0)
            #expect(chunkCount == 0)
            #expect(remainingArtifactCount == 0)
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

    @Test func migratesIntegerExtractionVersionTablesPreservingRowsAndCompatibilityColumns() throws {
        var config = Configuration()
        config.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(configuration: config)

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
        preMigrator.registerMigration("M011_AttachmentDataPlane", migrate: legacyAttachmentDataPlaneIntegerMigration)
        preMigrator.registerMigration("M012_AttachmentBlobStore", migrate: M012_AttachmentBlobStore.migrate)
        preMigrator.registerMigration("M013_ThreadBriefCacheIdentity", migrate: M013_ThreadBriefCacheIdentity.migrate)
        try preMigrator.migrate(dbQueue)

        try dbQueue.write { database in
            try AccountRecord(id: "a1", email: "a@example.com", createdAt: 1).insert(database)
            try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 1).insert(database)
            try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 1).insert(database)
            try AttachmentRecord(id: "att1", messageId: "m1", accountId: "a1").insert(database)
            try AttachmentBlobRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                relativePath: "a1/m1/att1",
                byteCount: 4,
                sha256: "hash",
                storedAt: 1
            ).insert(database)
            try database.execute(
                sql: """
                    INSERT INTO attachment_extraction (
                        account_id, message_id, attachment_id, extraction_version,
                        status, content_hash, mime, filename, byte_count,
                        created_at, updated_at, completed_at, text, unsupported_reason
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "a1", "m1", "att1", "pdf-text.v1",
                    "completed", "hash", "text/plain", "invoice.txt", 4,
                    1, 2, 3, "Extracted text", "none",
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO attachment_chunk (
                        account_id, message_id, attachment_id, extraction_version,
                        chunk_index, content_text, text, source_offset,
                        source_start, source_end, token_count, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "a1", "m1", "att1", "pdf-text.v1",
                    0, "Extracted text", "Extracted text", 0,
                    0, 14, 2, 1,
                ]
            )
            try database.execute(
                sql: """
                    INSERT INTO attachment_ai_artifact (
                        account_id, message_id, attachment_id, extraction_version,
                        artifact_kind, artifact_version, model_id, content_hash,
                        payload_json, content_json, task_id, prompt_version,
                        schema_version, input_fingerprint, created_at, updated_at,
                        generated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "a1", "m1", "att1", "pdf-text.v1",
                    "attachmentSummary", 1, "local", "hash",
                    "{\"payload\":true}", "{\"content\":true}", "attachmentSummary", "p1",
                    "s1", "hash", 1, 2, 3,
                ]
            )
        }

        try Migrator.migrate(dbQueue)

        try dbQueue.write { database in
            let extractionType = try columnType("attachment_extraction", "extraction_version", database)
            let chunkType = try columnType("attachment_chunk", "extraction_version", database)
            let artifactType = try columnType("attachment_ai_artifact", "extraction_version", database)
            let extractionColumns = try tableColumns("attachment_extraction", database)
            let artifactColumns = try tableColumns("attachment_ai_artifact", database)
            let preservedText = try String.fetchOne(database, sql: "SELECT text FROM attachment_extraction")
            let preservedContent = try String.fetchOne(database, sql: "SELECT content_json FROM attachment_ai_artifact")
            let artifactCount = try AttachmentAIArtifactRecord.fetchCount(database)

            #expect(extractionType == "TEXT")
            #expect(chunkType == "TEXT")
            #expect(artifactType == "TEXT")
            #expect(extractionColumns.contains("text"))
            #expect(extractionColumns.contains("unsupported_reason"))
            #expect(artifactColumns.contains("content_json"))
            #expect(artifactColumns.contains("task_id"))
            #expect(preservedText == "Extracted text")
            #expect(preservedContent == "{\"content\":true}")
            #expect(artifactCount == 1)

            let indexes = try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
            #expect(indexes.contains("idx_attachment_extraction_attachment"))
            #expect(indexes.contains("idx_attachment_chunk_attachment"))
            #expect(indexes.contains("idx_attachment_ai_artifact_attachment"))

            try AccountRecord.deleteOne(database, key: "a1")
            let blobCount = try AttachmentBlobRecord.fetchCount(database)
            let extractionCount = try AttachmentExtractionRecord.fetchCount(database)
            let chunkCount = try AttachmentChunkRecord.fetchCount(database)
            let remainingArtifactCount = try AttachmentAIArtifactRecord.fetchCount(database)
            #expect(blobCount == 0)
            #expect(extractionCount == 0)
            #expect(chunkCount == 0)
            #expect(remainingArtifactCount == 0)
        }
    }
}

private func columnType(_ table: String, _ column: String, _ database: Database) throws -> String? {
    try Row.fetchAll(database, sql: "PRAGMA table_info(\(table.sqlIdentifier))")
        .first { ($0["name"] as String?) == column }
        .flatMap { $0["type"] as String? }
}

private func tableColumns(_ table: String, _ database: Database) throws -> Set<String> {
    try Set(
        Row.fetchAll(database, sql: "PRAGMA table_info(\(table.sqlIdentifier))")
            .compactMap { $0["name"] as String? }
    )
}

private func legacyAttachmentDataPlaneIntegerMigration(_ database: Database) throws {
    try database.execute(sql: """
        CREATE TABLE attachment_extraction (
            account_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            attachment_id TEXT NOT NULL,
            extraction_version INTEGER NOT NULL,
            status TEXT NOT NULL,
            content_hash TEXT,
            mime TEXT,
            filename TEXT,
            byte_count INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            completed_at INTEGER,
            error_code TEXT,
            error_message TEXT,
            text TEXT,
            unsupported_reason TEXT,
            PRIMARY KEY (account_id, message_id, attachment_id, extraction_version),
            FOREIGN KEY (account_id, message_id, attachment_id)
                REFERENCES attachment(account_id, message_id, id)
                ON DELETE CASCADE
        )
        """)
    try database.execute(sql: """
        CREATE INDEX idx_attachment_extraction_attachment
        ON attachment_extraction(account_id, message_id, attachment_id)
        """)
    try database.execute(sql: """
        CREATE TABLE attachment_chunk (
            account_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            attachment_id TEXT NOT NULL,
            extraction_version INTEGER NOT NULL,
            chunk_index INTEGER NOT NULL,
            content_text TEXT NOT NULL,
            text TEXT,
            source_offset INTEGER,
            source_start INTEGER,
            source_end INTEGER,
            token_count INTEGER,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (account_id, message_id, attachment_id, extraction_version, chunk_index),
            FOREIGN KEY (account_id, message_id, attachment_id, extraction_version)
                REFERENCES attachment_extraction(account_id, message_id, attachment_id, extraction_version)
                ON DELETE CASCADE
        )
        """)
    try database.execute(sql: """
        CREATE INDEX idx_attachment_chunk_attachment
        ON attachment_chunk(account_id, message_id, attachment_id, extraction_version)
        """)
    try database.execute(sql: """
        CREATE TABLE attachment_ai_artifact (
            account_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            attachment_id TEXT NOT NULL,
            extraction_version INTEGER NOT NULL,
            artifact_kind TEXT NOT NULL,
            artifact_version INTEGER NOT NULL,
            model_id TEXT,
            content_hash TEXT,
            payload_json TEXT,
            content_json TEXT,
            task_id TEXT,
            prompt_version TEXT,
            schema_version TEXT,
            input_fingerprint TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            generated_at INTEGER,
            PRIMARY KEY (
                account_id, message_id, attachment_id,
                extraction_version, artifact_kind, artifact_version
            ),
            FOREIGN KEY (account_id, message_id, attachment_id, extraction_version)
                REFERENCES attachment_extraction(account_id, message_id, attachment_id, extraction_version)
                ON DELETE CASCADE
        )
        """)
    try database.execute(sql: """
        CREATE INDEX idx_attachment_ai_artifact_attachment
        ON attachment_ai_artifact(account_id, message_id, attachment_id, extraction_version)
        """)
    try database.execute(sql: """
        CREATE TABLE attachment_processing_job (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            attachment_id TEXT NOT NULL,
            job_kind TEXT NOT NULL,
            status TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            available_at INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            last_error_code TEXT,
            last_error_message TEXT,
            FOREIGN KEY (account_id, message_id, attachment_id)
                REFERENCES attachment(account_id, message_id, id)
                ON DELETE CASCADE
        )
        """)
}

private extension String {
    var sqlIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
