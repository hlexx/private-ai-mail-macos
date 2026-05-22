import GRDB
import Testing
@testable import Persistence

@Suite("Attachment Data Plane")
struct AttachmentDataPlaneTests {
    @Test func migrationCreatesAttachmentProcessingTablesAndIndexes() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        let tables = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        #expect(tables.contains("attachment_extraction"))
        #expect(tables.contains("attachment_chunk"))
        #expect(tables.contains("attachment_ai_artifact"))
        #expect(tables.contains("attachment_processing_job"))

        let indexes = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_attachment_%' ORDER BY name")
        }
        #expect(indexes.contains("idx_attachment_extraction_attachment"))
        #expect(indexes.contains("idx_attachment_chunk_attachment"))
        #expect(indexes.contains("idx_attachment_ai_artifact_attachment"))
        #expect(indexes.contains("idx_attachment_processing_job_attachment"))
        #expect(indexes.contains("idx_attachment_processing_job_status"))
    }

    @Test func attachmentDataPlaneRoundTrip() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try seedAttachment(db)
                try AttachmentExtractionRecord(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    extractionVersion: 1,
                    status: "succeeded",
                    contentHash: "sha256:abc",
                    mime: "application/pdf",
                    filename: "invoice.pdf",
                    byteCount: 4096,
                    createdAt: 100,
                    updatedAt: 120,
                    completedAt: 120
                ).insert(db)
                try AttachmentChunkRecord(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    extractionVersion: 1,
                    chunkIndex: 0,
                    contentText: "Invoice total is 42.00",
                    sourceReference: "page",
                    pageNumber: 1,
                    sourceStart: 0,
                    sourceEnd: 22,
                    tokenCount: 5,
                    createdAt: 121
                ).insert(db)
                try AttachmentAIArtifactRecord(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    extractionVersion: 1,
                    artifactKind: "summary",
                    artifactVersion: 1,
                    modelId: "local-test",
                    contentHash: "sha256:abc",
                    payloadJson: "{\"summary\":\"Invoice total is 42.00\"}",
                    createdAt: 130,
                    updatedAt: 130
                ).insert(db)
                try AttachmentProcessingJobRecord(
                    id: "job1",
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    jobKind: "extraction",
                    status: "queued",
                    priority: 10,
                    availableAt: 140,
                    createdAt: 140,
                    updatedAt: 140
                ).insert(db)
            }
        }

        let extraction = try db.read { db in
            try AttachmentExtractionRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM attachment_extraction
                    WHERE account_id = 'a1'
                      AND message_id = 'm1'
                      AND attachment_id = 'att1'
                      AND extraction_version = 1
                    """
            )
        }
        let chunk = try db.read { db in
            try AttachmentChunkRecord.fetchOne(db, sql: "SELECT * FROM attachment_chunk WHERE chunk_index = 0")
        }
        let artifact = try db.read { db in
            try AttachmentAIArtifactRecord.fetchOne(db, sql: "SELECT * FROM attachment_ai_artifact WHERE artifact_kind = 'summary'")
        }
        let job = try db.read { db in
            try AttachmentProcessingJobRecord.fetchOne(db, key: "job1")
        }

        #expect(extraction?.status == "succeeded")
        #expect(extraction?.contentHash == "sha256:abc")
        #expect(extraction?.byteCount == 4096)
        #expect(chunk?.contentText == "Invoice total is 42.00")
        #expect(chunk?.pageNumber == 1)
        #expect(artifact?.payloadJson == "{\"summary\":\"Invoice total is 42.00\"}")
        #expect(job?.priority == 10)
    }

    @Test func attachmentDataPlaneCascadeDeleteOnAccountRemoval() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try seedAttachment(db)
                try AttachmentExtractionRecord(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    extractionVersion: 1,
                    status: "succeeded",
                    createdAt: 100,
                    updatedAt: 100
                ).insert(db)
                try AttachmentChunkRecord(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    extractionVersion: 1,
                    chunkIndex: 0,
                    contentText: "text",
                    createdAt: 110
                ).insert(db)
                try AttachmentAIArtifactRecord(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    extractionVersion: 1,
                    artifactKind: "summary",
                    artifactVersion: 1,
                    payloadJson: "{}",
                    createdAt: 120,
                    updatedAt: 120
                ).insert(db)
                try AttachmentProcessingJobRecord(
                    id: "job1",
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    jobKind: "extraction",
                    status: "queued",
                    availableAt: 130,
                    createdAt: 130,
                    updatedAt: 130
                ).insert(db)
                _ = try AccountRecord.deleteOne(db, key: "a1")
            }
        }

        let counts = try db.read { db -> [Int] in
            [
                try AttachmentExtractionRecord.fetchCount(db),
                try AttachmentChunkRecord.fetchCount(db),
                try AttachmentAIArtifactRecord.fetchCount(db),
                try AttachmentProcessingJobRecord.fetchCount(db),
            ]
        }
        #expect(counts == [0, 0, 0, 0])
    }

    @Test func attachmentDataPlaneSaveIsIdempotentForReruns() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try seedAttachment(db)
                try AttachmentExtractionRecord(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    extractionVersion: 1,
                    status: "running",
                    createdAt: 100,
                    updatedAt: 100
                ).insert(db)

                try AttachmentExtractionRecord(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    extractionVersion: 1,
                    status: "succeeded",
                    contentHash: "sha256:new",
                    createdAt: 100,
                    updatedAt: 150,
                    completedAt: 150
                ).save(db)
            }
        }

        let count = try db.read { db in
            try AttachmentExtractionRecord.fetchCount(db)
        }
        let extraction = try db.read { db in
            try AttachmentExtractionRecord.fetchOne(db, sql: "SELECT * FROM attachment_extraction")
        }
        #expect(count == 1)
        #expect(extraction?.status == "succeeded")
        #expect(extraction?.contentHash == "sha256:new")
        #expect(extraction?.completedAt == 150)
    }

    private func seedAttachment(_ db: Database) throws {
        try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1).insert(db)
        try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2, messageCount: 1).insert(db)
        try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 2).insert(db)
        try AttachmentRecord(
            id: "att1",
            messageId: "m1",
            accountId: "a1",
            filename: "invoice.pdf",
            mime: "application/pdf",
            sizeBytes: 4096
        ).insert(db)
    }
}
