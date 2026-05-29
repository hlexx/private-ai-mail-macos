import GRDB
import Testing
@testable import Persistence

@Suite("Local Search Index Migration")
struct LocalSearchIndexMigrationTests {
    @Test func migrationCreatesSearchTablesAndMetadata() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        let tables = try db.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }
        #expect(tables.contains("mail_search_document"))
        #expect(tables.contains("mail_search_rebuild_state"))
        #expect(tables.contains("mail_search_fts"))

        let state = try db.read { database in
            try MailSearchRebuildStateRecord.fetchOne(database, key: LocalSearchIndexPersistence.metadataKey)
        }
        #expect(state?.schemaVersion == LocalSearchIndexPersistence.schemaVersion)
        #expect(state?.tokenizer == LocalSearchIndexPersistence.tokenizer)
        #expect(state?.needsRebuild == 1)
    }

    @Test func rebuildIndexesMessagesAttachmentsAndMailboxesWithoutAttachmentBytes() async throws {
        let db = try await seededSearchDatabase()

        try await DatabaseActor.shared.run {
            try db.write { database in
                try LocalSearchIndexPersistence.rebuildAll(in: database, now: 123)
            }
        }

        let document = try db.read { database in
            try MailSearchDocumentRecord.fetchOne(
                database,
                sql: "SELECT * FROM mail_search_document WHERE account_id = ? AND message_id = ?",
                arguments: ["a1", "m1"]
            )
        }
        #expect(document?.provider == "gmail")
        #expect(document?.subject == "Launch plan")
        #expect(document?.fromAddr == "sender@example.com")
        #expect(document?.toAddr == "team@example.com")
        #expect(document?.ccAddr == "lead@example.com")
        #expect(document?.snippet == "snippet text")
        #expect(document?.bodyText == nil)
        #expect(document?.normalizedBodyText == "Quarterly revenue deck")
        #expect(document?.attachmentFilenames == "roadmap.pdf")
        #expect(document?.attachmentMimes == "application/pdf")
        #expect(document?.canonicalMailboxes == "INBOX")
        #expect(document?.isUnread == 1)
        #expect(document?.isSent == 0)
        #expect(document?.hasAttachment == 1)

        let matches = try db.read { database in
            try String.fetchAll(
                database,
                sql: """
                    SELECT d.message_id
                    FROM mail_search_fts f
                    JOIN mail_search_document d ON d.id = f.rowid
                    WHERE mail_search_fts MATCH ?
                    ORDER BY d.message_id
                    """,
                arguments: ["revenue OR roadmap OR INBOX"]
            )
        }
        #expect(matches == ["m1"])

        let attachmentBytesMatches = try db.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM mail_search_fts WHERE mail_search_fts MATCH ?",
                arguments: ["hiddenpayload"]
            )
        }
        #expect(attachmentBytesMatches == 0)
    }

    @Test func upsertUpdatesAndDeleteRemovesSearchDocument() async throws {
        let db = try await seededSearchDatabase()

        try await DatabaseActor.shared.run {
            try db.write { database in
                try LocalSearchIndexPersistence.rebuildAll(in: database, now: 1)
                try database.execute(
                    sql: "UPDATE message SET body_text = ?, body_html = NULL WHERE account_id = ? AND id = ?",
                    arguments: ["fresh searchable body", "a1", "m1"]
                )
                try LocalSearchIndexPersistence.upsertMessage(accountId: "a1", messageId: "m1", in: database, now: 2)
            }
        }

        let freshMatches = try db.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM mail_search_fts WHERE mail_search_fts MATCH ?",
                arguments: ["fresh"]
            )
        }
        #expect(freshMatches == 1)

        let oldMatches = try db.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM mail_search_fts WHERE mail_search_fts MATCH ?",
                arguments: ["quarterly"]
            )
        }
        #expect(oldMatches == 0)

        try await DatabaseActor.shared.run {
            try db.write { database in
                try database.execute(
                    sql: "DELETE FROM message WHERE account_id = ? AND id = ?",
                    arguments: ["a1", "m1"]
                )
            }
        }

        let counts = try db.read { database -> [Int] in
            [
                try MailSearchDocumentRecord.fetchCount(database),
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM mail_search_fts WHERE mail_search_fts MATCH ?",
                    arguments: ["fresh"]
                ) ?? -1,
            ]
        }
        #expect(counts == [0, 0])
    }

    @Test func accountRemovalCascadesSearchDocumentsAndFtsRows() async throws {
        let db = try await seededSearchDatabase()

        try await DatabaseActor.shared.run {
            try db.write { database in
                try LocalSearchIndexPersistence.rebuildAll(in: database, now: 1)
                _ = try AccountRecord.deleteOne(database, key: "a1")
            }
        }

        let counts = try db.read { database -> [Int] in
            [
                try MailSearchDocumentRecord.fetchCount(database),
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM mail_search_fts WHERE mail_search_fts MATCH ?",
                    arguments: ["revenue"]
                ) ?? -1,
            ]
        }
        #expect(counts == [0, 0])
    }

    @Test func rebuildIsIdempotentAndClearsMetadataFlag() async throws {
        let db = try await seededSearchDatabase()

        try await DatabaseActor.shared.run {
            try db.write { database in
                try LocalSearchIndexPersistence.rebuildAll(in: database, now: 111)
                try LocalSearchIndexPersistence.markRebuildNeeded(in: database, now: 112)
                try LocalSearchIndexPersistence.rebuildAll(in: database, now: 222)
            }
        }

        let result = try db.read { database -> (Int, MailSearchRebuildStateRecord?) in
            (
                try MailSearchDocumentRecord.fetchCount(database),
                try MailSearchRebuildStateRecord.fetchOne(database, key: LocalSearchIndexPersistence.metadataKey)
            )
        }

        #expect(result.0 == 1)
        #expect(result.1?.needsRebuild == 0)
        #expect(result.1?.lastRebuiltAt == 222)
        #expect(result.1?.updatedAt == 222)
    }

    private func seededSearchDatabase() async throws -> AppDatabase {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { database in
                try AccountRecord(id: "a1", provider: "gmail", email: "user@example.com", createdAt: 1).insert(database)
                try ThreadRecord(
                    id: "t1",
                    accountId: "a1",
                    subject: "Launch plan",
                    snippet: "thread snippet",
                    lastMessageAt: 10,
                    messageCount: 1
                ).insert(database)
                try LabelRecord(
                    id: "INBOX",
                    accountId: "a1",
                    name: "Inbox",
                    type: .system
                ).insert(database)
                try ThreadLabelRecord(accountId: "a1", threadId: "t1", labelId: "INBOX").insert(database)
                try MessageRecord(
                    id: "m1",
                    threadId: "t1",
                    accountId: "a1",
                    fromAddr: "sender@example.com",
                    toAddr: "team@example.com",
                    ccAddr: "lead@example.com",
                    sentAt: 10,
                    snippet: "snippet text",
                    bodyHtml: "<p>Quarterly <strong>revenue</strong> deck</p>",
                    flags: 0
                ).insert(database)
                try AttachmentRecord(
                    id: "att1",
                    messageId: "m1",
                    accountId: "a1",
                    filename: "roadmap.pdf",
                    mime: "application/pdf",
                    sizeBytes: 42,
                    dataBase64: "hiddenpayload"
                ).insert(database)
            }
        }

        return db
    }
}
