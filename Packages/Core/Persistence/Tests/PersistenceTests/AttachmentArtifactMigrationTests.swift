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
                mime: "text/plain",
                text: "Amount due",
                unsupportedReason: nil,
                generatedAt: 2
            ).insert(database)

            try AttachmentChunkRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: "v1",
                chunkIndex: 0,
                sourceOffset: 0,
                text: "Amount due",
                tokenCount: 2
            ).insert(database)

            try AttachmentAIArtifactRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                taskId: "attachmentSummary",
                promptVersion: "attachment-summary.v1",
                schemaVersion: "attachment-summary.schema.v1",
                modelId: "local",
                extractionVersion: "v1",
                inputFingerprint: "abc",
                contentJSON: "{}",
                generatedAt: 3
            ).insert(database)

            #expect(try AttachmentAIArtifactRecord.fetchCount(database) == 1)
            try AccountRecord.deleteOne(database, key: "a1")
            #expect(try AttachmentBlobRecord.fetchCount(database) == 0)
            #expect(try AttachmentExtractionRecord.fetchCount(database) == 0)
            #expect(try AttachmentChunkRecord.fetchCount(database) == 0)
            #expect(try AttachmentAIArtifactRecord.fetchCount(database) == 0)
        }
    }
}
