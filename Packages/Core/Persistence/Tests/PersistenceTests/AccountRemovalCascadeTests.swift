import GRDB
import Testing
@testable import Persistence

@Suite("Account removal cascade")
struct AccountRemovalCascadeTests {
    @Test func deletingAccountCascadesAllAccountScopedLocalStores() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { database in
                try seedAccountScopedData(accountId: "a1", provider: "gmail", email: "a1@example.com", bodyTerm: "accountoneunique", in: database)
                try seedAccountScopedData(accountId: "a2", provider: "outlook", email: "a2@example.com", bodyTerm: "accounttwounique", in: database)
                try LocalSearchIndexPersistence.rebuildAll(in: database, now: 10)

                _ = try AccountRecord.deleteOne(database, key: "a1")
            }
        }

        let result = try db.read { database in
            AccountRemovalCounts(
                coveredAccountScopedTables: try discoveredAccountScopedTables(in: database),
                removedAccountRows: try countAccountScopedRows(accountId: "a1", in: database),
                remainingAccountRows: try countAccountScopedRows(accountId: "a2", in: database),
                removedSearchMatches: try ftsMatchCount("accountoneunique", in: database),
                remainingSearchMatches: try ftsMatchCount("accounttwounique", in: database)
            )
        }

        #expect(Set(result.coveredAccountScopedTables) == Set(accountScopedTables))
        #expect(result.removedAccountRows.allSatisfy { $0.value == 0 })
        #expect(result.remainingAccountRows.allSatisfy { $0.value == 1 })
        #expect(result.removedSearchMatches == 0)
        #expect(result.remainingSearchMatches == 1)
    }

    private func seedAccountScopedData(
        accountId: String,
        provider: String,
        email: String,
        bodyTerm: String,
        in database: Database
    ) throws {
        let threadId = "thread-\(accountId)"
        let messageId = "message-\(accountId)"
        let attachmentId = "attachment-\(accountId)"
        let draftId = "draft-\(accountId)"

        try AccountRecord(id: accountId, provider: provider, email: email, createdAt: 1).insert(database)
        try SyncStateRecord(accountId: accountId, historyId: "history-\(accountId)", status: "live").insert(database)
        try LabelRecord(id: "INBOX", accountId: accountId, name: "Inbox", type: .system).insert(database)
        try ThreadRecord(id: threadId, accountId: accountId, subject: "Subject", snippet: "Snippet", lastMessageAt: 2, messageCount: 1).insert(database)
        try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "INBOX").insert(database)
        try TrustedSenderRecord(accountId: accountId, fromAddr: "trusted-\(accountId)@example.com").insert(database)
        try MessageRecord(
            id: messageId,
            threadId: threadId,
            accountId: accountId,
            fromAddr: email,
            toAddr: "recipient@example.com",
            sentAt: 2,
            bodyText: "\(bodyTerm) local mail body"
        ).insert(database)
        try AttachmentRecord(
            id: attachmentId,
            messageId: messageId,
            accountId: accountId,
            filename: "invoice-\(accountId).pdf",
            mime: "application/pdf",
            sizeBytes: 64
        ).insert(database)
        try AttachmentBlobRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            relativePath: "\(accountId)/\(messageId)/\(attachmentId)",
            byteCount: 64,
            sha256: "sha-\(accountId)",
            storedAt: 3
        ).insert(database)
        try AttachmentExtractionRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            status: "extracted",
            contentHash: "hash-\(accountId)",
            mime: "application/pdf",
            filename: "invoice-\(accountId).pdf",
            byteCount: 64,
            createdAt: 3,
            updatedAt: 3,
            completedAt: 3,
            errorCode: nil,
            errorMessage: nil
        ).insert(database)
        try AttachmentChunkRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            chunkIndex: 0,
            contentText: "extracted \(accountId)",
            tokenCount: 2,
            createdAt: 3
        ).insert(database)
        try AttachmentAIArtifactRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            artifactKind: "attachmentSummary",
            artifactVersion: 1,
            modelId: "local",
            contentHash: "hash-\(accountId)",
            payloadJSON: "{}",
            createdAt: 4,
            updatedAt: 4
        ).insert(database)
        try database.execute(
            sql: """
                INSERT INTO attachment_processing_job (
                    id, account_id, message_id, attachment_id, job_kind, status,
                    priority, attempt_count, available_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, 'summarize', 'pending', 0, 0, 4, 4, 4)
                """,
            arguments: ["job-\(accountId)", accountId, messageId, attachmentId]
        )
        try ThreadBriefRecord(
            accountId: accountId,
            threadId: threadId,
            latestMessageId: messageId,
            summary: "Local summary",
            generatedAt: 4,
            promptVersion: "thread-brief.v1",
            schemaVersion: "thread-brief.schema.v1"
        ).insert(database)
        try GraphDeltaCheckpointRecord(
            accountId: accountId,
            folderId: "inbox",
            deltaURL: "https://graph.microsoft.com/delta?\(accountId)",
            updatedAt: 4
        ).insert(database)
        try DraftRecord(
            id: draftId,
            accountId: accountId,
            provider: provider,
            fromAddr: email,
            toAddr: "recipient@example.com",
            subject: "Draft",
            bodyText: "draft body",
            createdAt: 5,
            updatedAt: 5
        ).insert(database)
        try SendQueueItemRecord(
            id: "queue-\(accountId)",
            draftId: draftId,
            accountId: accountId,
            provider: provider,
            idempotencyKey: "idempotency-\(accountId)",
            status: "pending",
            fromAddr: email,
            toAddr: "recipient@example.com",
            subject: "Queued",
            bodyText: "queued body",
            createdAt: 5,
            updatedAt: 5
        ).insert(database)
    }

    private func countAccountScopedRows(accountId: String, in database: Database) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in accountScopedTables {
            let accountColumn = table == "account" ? "id" : "account_id"
            counts[table] = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM \(table.sqlIdentifier) WHERE \(accountColumn.sqlIdentifier) = ?",
                arguments: [accountId]
            ) ?? -1
        }
        return counts
    }

    private func discoveredAccountScopedTables(in database: Database) throws -> [String] {
        let tableNames = try String.fetchAll(
            database,
            sql: """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite_%'
                  AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """
        )

        var scopedTables = ["account"]
        for tableName in tableNames where tableName != "account" {
            let columns = try Row.fetchAll(
                database,
                sql: "PRAGMA table_info(\(tableName.sqlIdentifier))"
            ).map { row -> String in
                row["name"]
            }
            if columns.contains("account_id") {
                scopedTables.append(tableName)
            }
        }
        return scopedTables.sorted()
    }

    private func ftsMatchCount(_ term: String, in database: Database) throws -> Int {
        try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM mail_search_fts WHERE mail_search_fts MATCH ?",
            arguments: [term]
        ) ?? -1
    }

    private var accountScopedTables: [String] {
        [
            "account",
            "sync_state",
            "thread",
            "message",
            "attachment",
            "label",
            "thread_label",
            "trusted_sender",
            "thread_brief",
            "attachment_blob",
            "attachment_extraction",
            "attachment_chunk",
            "attachment_ai_artifact",
            "attachment_processing_job",
            "graph_delta_checkpoint",
            "mail_search_document",
            "draft",
            "send_queue_item",
        ]
    }
}

private struct AccountRemovalCounts {
    let coveredAccountScopedTables: [String]
    let removedAccountRows: [String: Int]
    let remainingAccountRows: [String: Int]
    let removedSearchMatches: Int
    let remainingSearchMatches: Int
}

private extension String {
    var sqlIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
