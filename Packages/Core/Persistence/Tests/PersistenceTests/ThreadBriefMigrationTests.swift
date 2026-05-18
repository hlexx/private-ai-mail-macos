import Testing
import GRDB
@testable import Persistence

@Suite("ThreadBrief Migration")
struct ThreadBriefMigrationTests {

    @Test func m006CreatesThreadBriefTable() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let tables = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        #expect(tables.contains("thread_brief"))
    }

    @Test func m006CreatesIndices() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let indexes = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_thread_brief%' ORDER BY name")
        }
        #expect(indexes.contains("idx_thread_brief_account"))
        #expect(indexes.contains("idx_thread_brief_request"))
        #expect(indexes.contains("idx_thread_brief_deadline"))
        #expect(indexes.count == 3)
    }

    @Test func threadBriefRecordRoundTrip() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadBriefRecord(
                    accountId: "a1",
                    threadId: "t1",
                    latestMessageId: "msg1",
                    summary: "Project update from Alice",
                    request: "approve invoice",
                    deadline: "2026-05-20",
                    risk: "budget overrun",
                    nextStep: "Review and approve",
                    confidence: 0.85,
                    evidenceJson: "[\"msg1\",\"msg2\"]",
                    language: "en",
                    generatedAt: 3000
                ).insert(db)
            }
        }

        let brief = try db.read { db in
            try ThreadBriefRecord.fetchOne(db, sql: "SELECT * FROM thread_brief WHERE account_id = 'a1' AND thread_id = 't1'")
        }
        #expect(brief != nil)
        #expect(brief?.accountId == "a1")
        #expect(brief?.threadId == "t1")
        #expect(brief?.latestMessageId == "msg1")
        #expect(brief?.summary == "Project update from Alice")
        #expect(brief?.request == "approve invoice")
        #expect(brief?.deadline == "2026-05-20")
        #expect(brief?.risk == "budget overrun")
        #expect(brief?.nextStep == "Review and approve")
        #expect(brief?.confidence == 0.85)
        #expect(brief?.evidenceJson == "[\"msg1\",\"msg2\"]")
        #expect(brief?.language == "en")
        #expect(brief?.generatedAt == 3000)
    }

    @Test func threadBriefCascadeDeleteOnAccountRemoval() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadBriefRecord(
                    accountId: "a1",
                    threadId: "t1",
                    latestMessageId: "msg1",
                    generatedAt: 3000
                ).insert(db)
            }
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                _ = try AccountRecord.deleteAll(db)
            }
        }

        let count = try db.read { db in
            try ThreadBriefRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    @Test func threadBriefUpsertOverwritesExistingRow() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try ThreadBriefRecord(
                    accountId: "a1",
                    threadId: "t1",
                    latestMessageId: "msg1",
                    summary: "Old summary",
                    generatedAt: 3000
                ).insert(db)
            }
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                let updated = ThreadBriefRecord(
                    accountId: "a1",
                    threadId: "t1",
                    latestMessageId: "msg2",
                    summary: "New summary",
                    request: "please confirm",
                    generatedAt: 4000
                )
                try updated.save(db)
            }
        }

        let count = try db.read { db in
            try ThreadBriefRecord.fetchCount(db)
        }
        #expect(count == 1)

        let brief = try db.read { db in
            try ThreadBriefRecord.fetchOne(db, sql: "SELECT * FROM thread_brief WHERE account_id = 'a1' AND thread_id = 't1'")
        }
        #expect(brief?.latestMessageId == "msg2")
        #expect(brief?.summary == "New summary")
        #expect(brief?.request == "please confirm")
        #expect(brief?.generatedAt == 4000)
    }
}

@Suite("Attachment CID Migration")
struct AttachmentCIDMigrationTests {

    @Test func m007AddsContentIdAndDataBase64Columns() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        let columns = try db.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('attachment') ORDER BY name")
        }
        #expect(columns.contains("content_id"))
        #expect(columns.contains("data_base64"))
    }

    @Test func attachmentRecordRoundTripWithCID() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 2000).insert(db)
                try AttachmentRecord(
                    id: "inline_logo@ex",
                    messageId: "m1",
                    accountId: "a1",
                    mime: "image/png",
                    contentId: "logo@ex",
                    dataBase64: "iVBORw0KGgo="
                ).insert(db)
            }
        }

        let att = try db.read { db in
            try AttachmentRecord.fetchOne(db, sql: "SELECT * FROM attachment WHERE id = 'inline_logo@ex'")
        }
        #expect(att != nil)
        #expect(att?.contentId == "logo@ex")
        #expect(att?.dataBase64 == "iVBORw0KGgo=")
        #expect(att?.mime == "image/png")
    }

    @Test func attachmentRecordWithoutCIDStillWorks() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { db in
                try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1000).insert(db)
                try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2000, messageCount: 1).insert(db)
                try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 2000).insert(db)
                try AttachmentRecord(
                    id: "att001",
                    messageId: "m1",
                    accountId: "a1",
                    filename: "doc.pdf",
                    mime: "application/pdf",
                    sizeBytes: 1024
                ).insert(db)
            }
        }

        let att = try db.read { db in
            try AttachmentRecord.fetchOne(db, sql: "SELECT * FROM attachment WHERE id = 'att001'")
        }
        #expect(att != nil)
        #expect(att?.contentId == nil)
        #expect(att?.dataBase64 == nil)
        #expect(att?.filename == "doc.pdf")
    }
}
