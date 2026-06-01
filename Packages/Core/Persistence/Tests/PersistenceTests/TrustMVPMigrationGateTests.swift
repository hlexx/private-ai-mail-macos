import GRDB
import Testing
@testable import Persistence

@Suite("Trust MVP migration gate")
struct TrustMVPMigrationGateTests {
    @Test func freshDatabaseMigrationCreatesTrustMVPReleaseGateSchema() throws {
        let db = try AppDatabase.openInMemorySync()

        let snapshot = try db.read { database in
            MigrationGateSchemaSnapshot(
                migrations: try String.fetchAll(
                    database,
                    sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"
                ),
                tables: try String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
                ),
                indexes: try String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'index' ORDER BY name"
                ),
                searchState: try MailSearchRebuildStateRecord.fetchOne(
                    database,
                    key: LocalSearchIndexPersistence.metadataKey
                )
            )
        }

        #expect(snapshot.migrations.contains("M018_LocalSearchAttachmentBuckets"))
        #expect(Set(snapshot.tables).isSuperset(of: Set(Self.releaseGateTables)))
        #expect(snapshot.indexes.contains("idx_graph_delta_checkpoint_account"))
        #expect(snapshot.indexes.contains("idx_send_queue_account_status"))
        #expect(snapshot.indexes.contains("idx_mail_search_document_filters"))
        #expect(snapshot.searchState?.schemaVersion == LocalSearchIndexPersistence.schemaVersion)
        #expect(snapshot.searchState?.tokenizer == LocalSearchIndexPersistence.tokenizer)
        #expect(snapshot.searchState?.needsRebuild == 1)
    }

    @Test func upgradeStyleMigrationPreservesSeededGmailDataAndAcceptsOutlookRows() throws {
        let dbQueue = try makeDatabaseQueue()
        try runMigrationsThroughM013(dbQueue)

        try dbQueue.write { database in
            try seedLegacyGmailRows(in: database)
        }

        try Migrator.migrate(dbQueue)

        try dbQueue.write { database in
            try seedOutlookRows(in: database)
            try LocalSearchIndexPersistence.rebuildAll(in: database, now: 2_000)
        }

        let snapshot = try dbQueue.read { database in
            MigrationGateDataSnapshot(
                providers: try String.fetchAll(
                    database,
                    sql: "SELECT provider FROM account ORDER BY provider"
                ),
                legacyGmailMessageBody: try String.fetchOne(
                    database,
                    sql: "SELECT body_text FROM message WHERE account_id = ? AND id = ?",
                    arguments: ["gmail-upgrade", "gmail-message"]
                ),
                legacyGmailAttachmentArtifactCount: try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM attachment_ai_artifact WHERE account_id = ?",
                    arguments: ["gmail-upgrade"]
                ) ?? -1,
                outlookGraphCheckpointCount: try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM graph_delta_checkpoint WHERE account_id = ?",
                    arguments: ["outlook-upgrade"]
                ) ?? -1,
                searchDocumentProviders: try String.fetchAll(
                    database,
                    sql: "SELECT provider FROM mail_search_document ORDER BY provider"
                ),
                gmailSearchMatches: try ftsMatchCount("legacygmailmarker", in: database),
                outlookSearchMatches: try ftsMatchCount("outlookmigrationmarker", in: database),
                draftProviders: try String.fetchAll(
                    database,
                    sql: "SELECT provider FROM draft ORDER BY provider"
                ),
                queuedSendProviders: try String.fetchAll(
                    database,
                    sql: "SELECT provider FROM send_queue_item ORDER BY provider"
                )
            )
        }

        #expect(snapshot.providers == ["gmail", "outlook"])
        #expect(snapshot.legacyGmailMessageBody == "legacygmailmarker body")
        #expect(snapshot.legacyGmailAttachmentArtifactCount == 1)
        #expect(snapshot.outlookGraphCheckpointCount == 1)
        #expect(snapshot.searchDocumentProviders == ["gmail", "outlook"])
        #expect(snapshot.gmailSearchMatches == 1)
        #expect(snapshot.outlookSearchMatches == 1)
        #expect(snapshot.draftProviders == ["outlook"])
        #expect(snapshot.queuedSendProviders == ["outlook"])
    }

    private static let releaseGateTables = [
        "account",
        "sync_state",
        "thread",
        "message",
        "label",
        "thread_label",
        "attachment",
        "attachment_blob",
        "attachment_extraction",
        "attachment_chunk",
        "attachment_ai_artifact",
        "attachment_processing_job",
        "graph_delta_checkpoint",
        "mail_search_document",
        "mail_search_rebuild_state",
        "mail_search_fts",
        "draft",
        "send_queue_item",
    ]

    private func makeDatabaseQueue() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try DatabaseQueue(configuration: configuration)
    }

    private func runMigrationsThroughM013(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("M001_InitialSchema", migrate: M001_InitialSchema.migrate)
        migrator.registerMigration("M002_Labels", migrate: M002_Labels.migrate)
        migrator.registerMigration("M003_TrustedSender", migrate: M003_TrustedSender.migrate)
        migrator.registerMigration("M004_TranslatedText", migrate: M004_TranslatedText.migrate)
        migrator.registerMigration("M005_ThreadLabelAccountId", migrate: M005_ThreadLabelAccountId.migrate)
        migrator.registerMigration("M006_ThreadBrief", migrate: M006_ThreadBrief.migrate)
        migrator.registerMigration("M007_AttachmentCID", migrate: M007_AttachmentCID.migrate)
        migrator.registerMigration("M008_BackfillInboxLabel", migrate: M008_BackfillInboxLabel.migrate)
        migrator.registerMigration("M009_BackfillInboxLabelV2", migrate: M009_BackfillInboxLabelV2.migrate)
        migrator.registerMigration("M010_SignalLabelReconcile", migrate: M010_SignalLabelReconcile.migrate)
        migrator.registerMigration("M011_AttachmentDataPlane", migrate: M011_AttachmentDataPlane.migrate)
        migrator.registerMigration("M012_AttachmentBlobStore", migrate: M012_AttachmentBlobStore.migrate)
        migrator.registerMigration("M013_ThreadBriefCacheIdentity", migrate: M013_ThreadBriefCacheIdentity.migrate)
        try migrator.migrate(dbQueue)
    }

    private func seedLegacyGmailRows(in database: Database) throws {
        try AccountRecord(
            id: "gmail-upgrade",
            provider: "gmail",
            email: "gmail-upgrade@example.com",
            createdAt: 1
        ).insert(database)
        try SyncStateRecord(accountId: "gmail-upgrade", historyId: "history-1", status: "live").insert(database)
        try LabelRecord(id: "INBOX", accountId: "gmail-upgrade", name: "Inbox", type: .system).insert(database)
        try ThreadRecord(
            id: "gmail-thread",
            accountId: "gmail-upgrade",
            subject: "Legacy Gmail",
            snippet: "Gmail migration",
            lastMessageAt: 10,
            messageCount: 1
        ).insert(database)
        try ThreadLabelRecord(accountId: "gmail-upgrade", threadId: "gmail-thread", labelId: "INBOX").insert(database)
        try MessageRecord(
            id: "gmail-message",
            threadId: "gmail-thread",
            accountId: "gmail-upgrade",
            fromAddr: "sender@example.com",
            toAddr: "gmail-upgrade@example.com",
            sentAt: 10,
            bodyText: "legacygmailmarker body"
        ).insert(database)
        try seedAttachmentAndArtifact(
            accountId: "gmail-upgrade",
            messageId: "gmail-message",
            attachmentId: "gmail-attachment",
            in: database
        )
    }

    private func seedOutlookRows(in database: Database) throws {
        try AccountRecord(
            id: "outlook-upgrade",
            provider: "outlook",
            email: "outlook-upgrade@example.com",
            createdAt: 2
        ).insert(database)
        try LabelRecord(
            id: "outlook-folder-inbox",
            accountId: "outlook-upgrade",
            name: "Inbox",
            type: .system
        ).insert(database)
        try ThreadRecord(
            id: "outlook-thread",
            accountId: "outlook-upgrade",
            subject: "Outlook migration",
            snippet: "Outlook-compatible row",
            lastMessageAt: 20,
            messageCount: 1
        ).insert(database)
        try ThreadLabelRecord(
            accountId: "outlook-upgrade",
            threadId: "outlook-thread",
            labelId: "outlook-folder-inbox"
        ).insert(database)
        try MessageRecord(
            id: "outlook-message",
            threadId: "outlook-thread",
            accountId: "outlook-upgrade",
            fromAddr: "sender@outlook.example.com",
            toAddr: "outlook-upgrade@example.com",
            sentAt: 20,
            bodyText: "outlookmigrationmarker body"
        ).insert(database)
        try AttachmentRecord(
            id: "outlook-attachment",
            messageId: "outlook-message",
            accountId: "outlook-upgrade",
            filename: "outlook-plan.pdf",
            mime: "application/pdf",
            sizeBytes: 128
        ).insert(database)
        try GraphDeltaCheckpointRecord(
            accountId: "outlook-upgrade",
            folderId: "inbox",
            deltaURL: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=opaque",
            updatedAt: 20
        ).insert(database)
        try DraftRecord(
            id: "outlook-draft",
            accountId: "outlook-upgrade",
            provider: "outlook",
            fromAddr: "outlook-upgrade@example.com",
            toAddr: "recipient@example.com",
            subject: "Outlook draft",
            bodyText: "Outlook draft stays local",
            createdAt: 21,
            updatedAt: 21
        ).insert(database)
        try SendQueueItemRecord(
            id: "outlook-queue",
            draftId: "outlook-draft",
            accountId: "outlook-upgrade",
            provider: "outlook",
            idempotencyKey: "outlook-idempotency",
            status: "pending",
            fromAddr: "outlook-upgrade@example.com",
            toAddr: "recipient@example.com",
            subject: "Outlook queued send",
            bodyText: "Queued Outlook body stays local",
            createdAt: 22,
            updatedAt: 22
        ).insert(database)
    }

    private func seedAttachmentAndArtifact(
        accountId: String,
        messageId: String,
        attachmentId: String,
        in database: Database
    ) throws {
        try AttachmentRecord(
            id: attachmentId,
            messageId: messageId,
            accountId: accountId,
            filename: "legacy.pdf",
            mime: "application/pdf",
            sizeBytes: 96
        ).insert(database)
        try AttachmentBlobRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            relativePath: "\(accountId)/\(messageId)/\(attachmentId)",
            byteCount: 96,
            sha256: "sha-\(attachmentId)",
            storedAt: 11
        ).insert(database)
        try AttachmentExtractionRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            status: "extracted",
            contentHash: "hash-\(attachmentId)",
            mime: "application/pdf",
            filename: "legacy.pdf",
            byteCount: 96,
            createdAt: 11,
            updatedAt: 11,
            completedAt: 11,
            errorCode: nil,
            errorMessage: nil
        ).insert(database)
        try AttachmentChunkRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            chunkIndex: 0,
            contentText: "Legacy local extraction",
            tokenCount: 3,
            createdAt: 11
        ).insert(database)
        try AttachmentAIArtifactRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            artifactKind: "attachmentSummary",
            artifactVersion: 1,
            modelId: "local",
            contentHash: "hash-\(attachmentId)",
            payloadJSON: "{}",
            createdAt: 12,
            updatedAt: 12
        ).insert(database)
    }

    private func ftsMatchCount(_ term: String, in database: Database) throws -> Int {
        try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM mail_search_fts WHERE mail_search_fts MATCH ?",
            arguments: [term]
        ) ?? -1
    }
}

private struct MigrationGateSchemaSnapshot {
    var migrations: [String]
    var tables: [String]
    var indexes: [String]
    var searchState: MailSearchRebuildStateRecord?
}

private struct MigrationGateDataSnapshot {
    var providers: [String]
    var legacyGmailMessageBody: String?
    var legacyGmailAttachmentArtifactCount: Int
    var outlookGraphCheckpointCount: Int
    var searchDocumentProviders: [String]
    var gmailSearchMatches: Int
    var outlookSearchMatches: Int
    var draftProviders: [String]
    var queuedSendProviders: [String]
}
