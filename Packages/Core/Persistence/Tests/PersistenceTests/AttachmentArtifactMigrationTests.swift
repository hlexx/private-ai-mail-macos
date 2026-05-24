import GRDB
import Testing
@testable import Persistence

@Suite("Attachment AI Artifact Migration")
struct AttachmentArtifactMigrationTests {
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

            let tables = try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            #expect(tables.contains("attachment_extraction"))
            #expect(tables.contains("attachment_chunk"))
            #expect(tables.contains("attachment_ai_artifact"))
            #expect(tables.contains("attachment_processing_job"))
            #expect(tables.contains("attachment_blob"))
        }
    }
}
