import GRDB
import Testing
@testable import Persistence

@Suite("Draft and Send Queue Persistence")
struct DraftSendQueuePersistenceTests {
    @Test func migrationCreatesDraftAndSendQueueTablesWithLocalBodyColumns() throws {
        let db = try AppDatabase.openInMemorySync()

        let tables = try db.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }
        #expect(tables.contains("draft"))
        #expect(tables.contains("send_queue_item"))

        let draftColumns = try db.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(draft)").map { row -> String in
                row["name"]
            }
        }
        let queueColumns = try db.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(send_queue_item)").map { row -> String in
                row["name"]
            }
        }

        #expect(draftColumns.contains("body_text"))
        #expect(draftColumns.contains("body_html"))
        #expect(draftColumns.contains("body_storage"))
        #expect(queueColumns.contains("idempotency_key"))
        #expect(queueColumns.contains("status"))
        #expect(queueColumns.contains("attempts"))
        #expect(queueColumns.contains("sanitized_error_category"))
    }

    @Test func draftStoreSavesFetchesAndDeletesLocalSQLiteBody() async throws {
        let db = try await seededDatabase()
        let store = LocalDraftStore(db: db)
        let draft = makeDraft()

        let saved = try await store.save(draft)
        let fetched = try store.fetch(id: saved.id)
        #expect(fetched == draft)
        #expect(fetched?.bodyStorage == "sqlite")
        #expect(fetched?.bodyText == "Draft body stays local")

        try await store.delete(id: saved.id)
        #expect(try store.fetch(id: saved.id) == nil)
    }

    @Test func sendQueueStoreInsertsFetchesAndEnforcesIdempotency() async throws {
        let db = try await seededDatabase()
        let draftStore = LocalDraftStore(db: db)
        let queueStore = LocalSendQueueStore(db: db)
        _ = try await draftStore.save(makeDraft())

        let item = makeQueueItem()
        _ = try await queueStore.insert(item)

        #expect(try queueStore.fetch(id: item.id) == item)
        #expect(try queueStore.fetch(
            provider: item.provider,
            accountId: item.accountId,
            idempotencyKey: item.idempotencyKey
        ) == item)

        let duplicate = makeQueueItem(id: "queue-2")
        let duplicateRejected = await rejects {
            _ = try await queueStore.insert(duplicate)
        }
        #expect(duplicateRejected)
    }

    @Test func accountDeletionCascadesDraftsAndSendQueueItems() async throws {
        let db = try await seededDatabase()

        try await DatabaseActor.shared.run {
            try db.write { database in
                try makeDraft().insert(database)
                try makeQueueItem().insert(database)
                #expect(try DraftRecord.fetchCount(database) == 1)
                #expect(try SendQueueItemRecord.fetchCount(database) == 1)
                _ = try AccountRecord.deleteOne(database, key: "account-1")
            }
        }

        let counts = try db.read { database in
            [
                try AccountRecord.fetchCount(database),
                try DraftRecord.fetchCount(database),
                try SendQueueItemRecord.fetchCount(database),
            ]
        }
        #expect(counts == [0, 0, 0])
    }

    @Test func retryMetadataAndSanitizedFailureRoundTrip() async throws {
        let db = try await seededDatabase()
        let draftStore = LocalDraftStore(db: db)
        let queueStore = LocalSendQueueStore(db: db)
        _ = try await draftStore.save(makeDraft())
        let item = makeQueueItem(
            status: "retryScheduled",
            attempts: 2,
            nextAttemptAt: 1_900,
            lastAttemptAt: 1_800,
            sanitizedErrorCategory: "rateLimited",
            sanitizedErrorCode: "429",
            sanitizedErrorMessage: "Provider asked us to retry later.",
            retryAfterSeconds: 300
        )

        _ = try await queueStore.insert(item)

        let fetched = try queueStore.fetch(id: item.id)
        #expect(fetched?.status == "retryScheduled")
        #expect(fetched?.attempts == 2)
        #expect(fetched?.maxAttempts == 5)
        #expect(fetched?.nextAttemptAt == 1_900)
        #expect(fetched?.lastAttemptAt == 1_800)
        #expect(fetched?.sanitizedErrorCategory == "rateLimited")
        #expect(fetched?.sanitizedErrorCode == "429")
        #expect(fetched?.sanitizedErrorMessage == "Provider asked us to retry later.")
        #expect(fetched?.retryAfterSeconds == 300)
    }

    private func seededDatabase() async throws -> AppDatabase {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }

        try await DatabaseActor.shared.run {
            try db.write { database in
                try AccountRecord(
                    id: "account-1",
                    provider: "gmail",
                    email: "user@example.com",
                    createdAt: 1_000
                ).insert(database)
            }
        }

        return db
    }

    private func makeDraft(id: String = "draft-1") -> DraftRecord {
        DraftRecord(
            id: id,
            accountId: "account-1",
            provider: "gmail",
            fromAddr: "User <user@example.com>",
            toAddr: "Recipient <recipient@example.com>",
            subject: "Draft subject",
            bodyText: "Draft body stays local",
            threadId: "thread-1",
            replyToProviderMessageId: "provider-parent",
            rfcMessageId: "<draft@hlexx.privateaimail>",
            rfcInReplyTo: "<parent@example.com>",
            rfcReferencesJson: #"["<parent@example.com>"]"#,
            createdAt: 1_000,
            updatedAt: 1_001
        )
    }

    private func makeQueueItem(
        id: String = "queue-1",
        status: String = "pending",
        attempts: Int = 0,
        nextAttemptAt: Int? = nil,
        lastAttemptAt: Int? = nil,
        sanitizedErrorCategory: String? = nil,
        sanitizedErrorCode: String? = nil,
        sanitizedErrorMessage: String? = nil,
        retryAfterSeconds: Int? = nil
    ) -> SendQueueItemRecord {
        SendQueueItemRecord(
            id: id,
            draftId: "draft-1",
            accountId: "account-1",
            provider: "gmail",
            idempotencyKey: "idempotency-1",
            status: status,
            fromAddr: "User <user@example.com>",
            toAddr: "Recipient <recipient@example.com>",
            subject: "Draft subject",
            bodyText: "Queued body snapshot stays local",
            threadId: "thread-1",
            replyToProviderMessageId: "provider-parent",
            rfcMessageId: "<queued@hlexx.privateaimail>",
            rfcInReplyTo: "<parent@example.com>",
            rfcReferencesJson: #"["<parent@example.com>"]"#,
            attempts: attempts,
            maxAttempts: 5,
            nextAttemptAt: nextAttemptAt,
            lastAttemptAt: lastAttemptAt,
            createdAt: 1_100,
            updatedAt: 1_101,
            sanitizedErrorCategory: sanitizedErrorCategory,
            sanitizedErrorCode: sanitizedErrorCode,
            sanitizedErrorMessage: sanitizedErrorMessage,
            retryAfterSeconds: retryAfterSeconds
        )
    }

    private func rejects(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            return false
        } catch {
            return true
        }
    }
}
