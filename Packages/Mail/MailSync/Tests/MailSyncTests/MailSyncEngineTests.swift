import Testing
import Foundation
@testable import MailSync
import MailProviders
import Persistence
import GRDB

@Suite("MailSyncEngine")
struct MailSyncEngineTests {

    private func makeDB() async throws -> AppDatabase {
        try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
    }

    private func seedAccount(_ db: AppDatabase, id: String = "acc1") async throws {
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                let account = AccountRecord(
                    id: id,
                    provider: "gmail",
                    email: "test@gmail.com",
                    createdAt: Int(Date().timeIntervalSince1970)
                )
                try account.insert(dbConn)
                let syncState = SyncStateRecord(accountId: id, status: "idle")
                try syncState.insert(dbConn)
            }
        }
    }

    private func makeThread(id: String, messageIds: [String]) -> GmailDTO.Thread {
        let messages = messageIds.map { makeMessage(id: $0, threadId: id) }
        return GmailDTO.Thread(id: id, historyId: "100", messages: messages)
    }

    private func makeThread(
        id: String,
        messageIds: [String],
        attachmentsByMessage: [String: [String]]
    ) -> GmailDTO.Thread {
        let messages = messageIds.map { msgId in
            makeMessage(
                id: msgId,
                threadId: id,
                attachmentIds: attachmentsByMessage[msgId] ?? []
            )
        }
        return GmailDTO.Thread(id: id, historyId: "100", messages: messages)
    }

    private func makeMessage(
        id: String,
        threadId: String,
        labelIds: [String] = ["INBOX"],
        attachmentIds: [String] = []
    ) -> GmailDTO.Message {
        let attachmentParts = attachmentIds.map { attachmentId in
            GmailDTO.MessagePart(
                mimeType: "application/pdf",
                filename: "\(attachmentId).pdf",
                body: GmailDTO.MessagePartBody(attachmentId: attachmentId, size: 42)
            )
        }
        return GmailDTO.Message(
            id: id,
            threadId: threadId,
            labelIds: labelIds,
            snippet: "snippet-\(id)",
            historyId: "100",
            internalDate: "\(Int(Date().timeIntervalSince1970 * 1000))",
            payload: GmailDTO.MessagePart(
                headers: [
                    GmailDTO.MessagePartHeader(name: "Subject", value: "Test subject \(threadId)"),
                    GmailDTO.MessagePartHeader(name: "From", value: "sender@example.com"),
                ],
                parts: attachmentParts
            )
        )
    }

    @Test func bootstrapInsertsThreadsAndMessages() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        let api = MockGmailAPI()
        // Return 3 messages across 2 threads
        api.listMessagesResults = [
            .success(GmailDTO.MessageList(
                messages: [
                    GmailDTO.MessageRef(id: "m1", threadId: "t1"),
                    GmailDTO.MessageRef(id: "m2", threadId: "t1"),
                    GmailDTO.MessageRef(id: "m3", threadId: "t2"),
                ],
                nextPageToken: nil
            ))
        ]
        api.getThreadResults = [
            "t1": .success(makeThread(id: "t1", messageIds: ["m1", "m2"])),
            "t2": .success(makeThread(id: "t2", messageIds: ["m3"])),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.bootstrap()

        let threadCount = try db.read { dbConn in
            try ThreadRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        let messageCount = try db.read { dbConn in
            try MessageRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }

        #expect(threadCount == 2)
        #expect(messageCount == 3)
        let searchDocumentCount = try db.read { dbConn in
            try MailSearchDocumentRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        #expect(searchDocumentCount == 3)
        let state = await engine.state
        #expect(state == .live)
    }

    @Test func incrementalSyncAddsNewMessage() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        // Seed an existing thread with one message
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                let thread = ThreadRecord(
                    id: "t1", accountId: "acc1", subject: "Old subject",
                    lastMessageAt: 1000, messageCount: 1
                )
                try thread.insert(dbConn)
                let msg = MessageRecord(
                    id: "m1", threadId: "t1", accountId: "acc1", sentAt: 1000
                )
                try msg.insert(dbConn)
                var syncState = try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])!
                syncState.historyId = "50"
                try syncState.update(dbConn)
            }
        }

        let api = MockGmailAPI()
        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "51",
                        messagesAdded: [
                            GmailDTO.HistoryMessageAdded(
                                message: GmailDTO.Message(id: "m2", threadId: "t1")
                            )
                        ]
                    )
                ],
                nextPageToken: nil,
                historyId: "60"
            ))
        ]
        // Re-fetch thread with both messages
        api.getThreadResults = [
            "t1": .success(makeThread(id: "t1", messageIds: ["m1", "m2"])),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        // Set engine to live state first by accessing internals indirectly
        // We'll just call refresh - it checks for live or idle state
        await engine.refresh()

        let messageCount = try db.read { dbConn in
            try MessageRecord.filter(Column("account_id") == "acc1" && Column("thread_id") == "t1").fetchCount(dbConn)
        }
        #expect(messageCount == 2)

        // Verify history ID was updated
        let syncState = try db.read { dbConn in
            try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])
        }
        #expect(syncState?.historyId == "60")
    }

    @Test func incrementalSyncKeepsOriginalHistoryIdAcrossPages() async throws {
        let db = try await makeDB()
        try await seedAccount(db)
        try await setHistoryId("50", db: db)

        let api = MockGmailAPI()
        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "51",
                        messagesAdded: [
                            GmailDTO.HistoryMessageAdded(
                                message: GmailDTO.Message(id: "m1", threadId: "t1")
                            )
                        ]
                    ),
                ],
                nextPageToken: "page-2",
                historyId: "60"
            )),
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "52",
                        labelsAdded: [
                            GmailDTO.HistoryLabelAdded(
                                message: GmailDTO.Message(id: "m2", threadId: "t2"),
                                labelIds: ["STARRED"]
                            )
                        ]
                    ),
                ],
                nextPageToken: nil,
                historyId: "70"
            )),
        ]
        api.getThreadResults = [
            "t1": .success(makeThread(id: "t1", messageIds: ["m1"])),
            "t2": .success(makeThread(id: "t2", messageIds: ["m2"])),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        #expect(api.listHistoryCallArguments.count == 2)
        #expect(api.listHistoryCallArguments[0].startHistoryId == "50")
        #expect(api.listHistoryCallArguments[0].pageToken == nil)
        #expect(api.listHistoryCallArguments[1].startHistoryId == "50")
        #expect(api.listHistoryCallArguments[1].pageToken == "page-2")

        let syncState = try db.read { dbConn in
            try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])
        }
        #expect(syncState?.historyId == "70")
        #expect(Set(api.getThreadCalledIds) == ["t1", "t2"])
    }

    @Test func incrementalSyncDoesNotUseIntermediateHistoryIdForNextPage() async throws {
        let db = try await makeDB()
        try await seedAccount(db)
        try await setHistoryId("50", db: db)

        let api = MockGmailAPI()
        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [],
                nextPageToken: "page-2",
                historyId: "60"
            )),
            .success(GmailDTO.HistoryResponse(
                history: [],
                nextPageToken: nil,
                historyId: "70"
            )),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        #expect(api.listHistoryCallArguments.map(\.startHistoryId) == ["50", "50"])
        #expect(api.listHistoryCallArguments.map(\.pageToken) == [nil, "page-2"])

        let syncState = try db.read { dbConn in
            try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])
        }
        #expect(syncState?.historyId == "70")
    }

    @Test func incrementalSyncDeletesMessage() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        // Seed thread with 2 messages
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                let thread = ThreadRecord(
                    id: "t1", accountId: "acc1", subject: "Subject",
                    lastMessageAt: 1000, messageCount: 2
                )
                try thread.insert(dbConn)
                try MessageRecord(id: "m1", threadId: "t1", accountId: "acc1", sentAt: 1000).insert(dbConn)
                try MessageRecord(id: "m2", threadId: "t1", accountId: "acc1", sentAt: 2000).insert(dbConn)
                try LocalSearchIndexPersistence.rebuildAll(in: dbConn, now: 1)
                var syncState = try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])!
                syncState.historyId = "50"
                try syncState.update(dbConn)
            }
        }

        let api = MockGmailAPI()
        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "51",
                        messagesDeleted: [
                            GmailDTO.HistoryMessageDeleted(
                                message: GmailDTO.Message(id: "m2", threadId: "t1")
                            )
                        ]
                    )
                ],
                nextPageToken: nil,
                historyId: "60"
            ))
        ]
        // Re-fetch returns thread with only m1
        api.getThreadResults = [
            "t1": .success(makeThread(id: "t1", messageIds: ["m1"])),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        let messageCount = try db.read { dbConn in
            try MessageRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        #expect(messageCount == 1)

        let thread = try db.read { dbConn in
            try ThreadRecord.fetchOne(dbConn, key: ["account_id": "acc1", "id": "t1"])
        }
        #expect(thread?.messageCount == 1)

        let searchMessageIds = try db.read { dbConn in
            try String.fetchAll(
                dbConn,
                sql: """
                SELECT message_id FROM mail_search_document
                WHERE account_id = ?
                ORDER BY message_id
                """,
                arguments: ["acc1"]
            )
        }
        #expect(searchMessageIds == ["m1"])
    }

    @Test func incrementalLabelRefreshPreservesAttachmentArtifacts() async throws {
        let db = try await makeDB()
        try await seedAccount(db)
        try await seedThreadWithAttachmentArtifacts(
            db,
            threadId: "t1",
            messageId: "m1",
            attachmentIds: ["att1"]
        )
        try await setHistoryId("50", db: db)

        let api = MockGmailAPI()
        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "51",
                        labelsAdded: [
                            GmailDTO.HistoryLabelAdded(
                                message: GmailDTO.Message(id: "m1", threadId: "t1"),
                                labelIds: ["STARRED"]
                            )
                        ]
                    ),
                ],
                nextPageToken: nil,
                historyId: "60"
            )),
        ]
        api.getThreadResults = [
            "t1": .success(makeThread(
                id: "t1",
                messageIds: ["m1"],
                attachmentsByMessage: ["m1": ["att1"]]
            )),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        let counts = try await artifactCounts(db, attachmentId: "att1")
        #expect(counts.blobs == 1)
        #expect(counts.extractions == 1)
        #expect(counts.chunks == 1)
        #expect(counts.artifacts == 1)
    }

    @Test func incrementalRefreshDeletesArtifactsOnlyForRemovedAttachment() async throws {
        let db = try await makeDB()
        try await seedAccount(db)
        try await seedThreadWithAttachmentArtifacts(
            db,
            threadId: "t1",
            messageId: "m1",
            attachmentIds: ["att1", "att2"]
        )
        try await setHistoryId("50", db: db)

        let api = MockGmailAPI()
        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "51",
                        labelsAdded: [
                            GmailDTO.HistoryLabelAdded(
                                message: GmailDTO.Message(id: "m1", threadId: "t1"),
                                labelIds: ["INBOX"]
                            )
                        ]
                    ),
                ],
                nextPageToken: nil,
                historyId: "60"
            )),
        ]
        api.getThreadResults = [
            "t1": .success(makeThread(
                id: "t1",
                messageIds: ["m1"],
                attachmentsByMessage: ["m1": ["att1"]]
            )),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        let preserved = try await artifactCounts(db, attachmentId: "att1")
        #expect(preserved.blobs == 1)
        #expect(preserved.extractions == 1)
        #expect(preserved.chunks == 1)
        #expect(preserved.artifacts == 1)

        let removed = try await artifactCounts(db, attachmentId: "att2")
        #expect(removed.blobs == 0)
        #expect(removed.extractions == 0)
        #expect(removed.chunks == 0)
        #expect(removed.artifacts == 0)
    }

    @Test func rateLimitedTriggersAPausedState() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        let api = MockGmailAPI()
        api.listMessagesResults = [
            .failure(GmailAPIError.rateLimited(retryAfter: 1.0))
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.bootstrap()

        let state = await engine.state
        #expect(state == .paused)
    }

    @Test func syncErrorsUseUserActionableFailureCopy() {
        let offline = SyncError.bootstrapFailed(GmailAPIError.networkError(URLError(.notConnectedToInternet)))
        let scope = SyncError.incrementalFailed(GmailAPIError.insufficientScope)
        let rateLimited = SyncError.rateLimited(retryAfter: 42)

        #expect(offline.userActionableFailure.category == .offline)
        #expect(offline.localizedDescription == "Sync cannot reach Gmail while offline. Check your connection and try again.")
        #expect(scope.userActionableFailure.category == .insufficientScope)
        #expect(scope.localizedDescription == "Re-authorize Gmail so Re:Box has permission to sync mail.")
        #expect(rateLimited.userActionableFailure.category == .rateLimit)
        #expect(rateLimited.localizedDescription == "Gmail is rate-limiting sync. Re:Box will retry in 42s.")
    }

    @Test func reBootstrapIsIdempotent() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        let api = MockGmailAPI()
        let threadDTO = makeThread(id: "t1", messageIds: ["m1", "m2"])

        api.listMessagesResults = [
            .success(GmailDTO.MessageList(
                messages: [
                    GmailDTO.MessageRef(id: "m1", threadId: "t1"),
                    GmailDTO.MessageRef(id: "m2", threadId: "t1"),
                ],
                nextPageToken: nil
            ))
        ]
        api.getThreadResults = ["t1": .success(threadDTO)]

        // First bootstrap
        let engine1 = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine1.bootstrap()

        let countAfterFirst = try db.read { dbConn in
            try ThreadRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        let msgCountAfterFirst = try db.read { dbConn in
            try MessageRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }

        // Reset mock for second bootstrap
        api.listMessagesResults = [
            .success(GmailDTO.MessageList(
                messages: [
                    GmailDTO.MessageRef(id: "m1", threadId: "t1"),
                    GmailDTO.MessageRef(id: "m2", threadId: "t1"),
                ],
                nextPageToken: nil
            ))
        ]

        let engine2 = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine2.bootstrap()

        let countAfterSecond = try db.read { dbConn in
            try ThreadRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        let msgCountAfterSecond = try db.read { dbConn in
            try MessageRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        let searchCountAfterSecond = try db.read { dbConn in
            try MailSearchDocumentRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }

        #expect(countAfterFirst == countAfterSecond)
        #expect(msgCountAfterFirst == msgCountAfterSecond)
        #expect(countAfterSecond == 1)
        #expect(msgCountAfterSecond == 2)
        #expect(searchCountAfterSecond == 2)
    }
    @Test func syncReplacesLocalSentMessageWithCanonical() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        // Simulate a locally-inserted sent message (as ComposeService would)
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                let thread = ThreadRecord(
                    id: "t1", accountId: "acc1", subject: "My sent msg",
                    lastMessageAt: 5000, messageCount: 1
                )
                try thread.insert(dbConn)
                let msg = MessageRecord(
                    id: "m1", threadId: "t1", accountId: "acc1",
                    fromAddr: "me@gmail.com",
                    toAddr: "them@example.com",
                    sentAt: 5000,
                    snippet: "local snippet",
                    bodyText: "local body",
                    flags: MessageRecord.sentByMe | MessageRecord.read
                )
                try msg.insert(dbConn)
                try LocalSearchIndexPersistence.upsertMessage(accountId: "acc1", messageId: "m1", in: dbConn, now: 1)
                var syncState = try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])!
                syncState.historyId = "50"
                try syncState.update(dbConn)
            }
        }

        // Verify local record exists
        let localMsg = try db.read { dbConn in
            try MessageRecord.fetchOne(dbConn, key: ["account_id": "acc1", "id": "m1"])
        }
        #expect(localMsg?.snippet == "local snippet")
        #expect(localMsg?.flags == MessageRecord.sentByMe | MessageRecord.read)

        // Now simulate incremental sync that re-fetches the thread with canonical data
        let api = MockGmailAPI()
        let canonicalMessage = GmailDTO.Message(
            id: "m1",
            threadId: "t1",
            labelIds: ["SENT"],
            snippet: "canonical snippet from Gmail",
            historyId: "60",
            internalDate: "5000000",
            payload: GmailDTO.MessagePart(
                headers: [
                    GmailDTO.MessagePartHeader(name: "Subject", value: "My sent msg"),
                    GmailDTO.MessagePartHeader(name: "From", value: "me@gmail.com"),
                ]
            )
        )
        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "51",
                        messagesAdded: [
                            GmailDTO.HistoryMessageAdded(
                                message: GmailDTO.Message(id: "m1", threadId: "t1")
                            )
                        ]
                    )
                ],
                nextPageToken: nil,
                historyId: "60"
            ))
        ]
        api.getThreadResults = [
            "t1": .success(GmailDTO.Thread(
                id: "t1",
                historyId: "60",
                messages: [canonicalMessage]
            )),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        // After sync, the canonical record replaces the local one (UPSERT)
        let syncedMsg = try db.read { dbConn in
            try MessageRecord.fetchOne(dbConn, key: ["account_id": "acc1", "id": "m1"])
        }
        #expect(syncedMsg != nil)
        #expect(syncedMsg?.snippet == "canonical snippet from Gmail")
        // sentByMe flag preserved because SENT label is present
        #expect((syncedMsg?.flags ?? 0) & MessageRecord.sentByMe != 0)

        // Only one message in DB — no duplicates
        let totalMessages = try db.read { dbConn in
            try MessageRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        #expect(totalMessages == 1)

        // Thread also updated
        let syncedThread = try db.read { dbConn in
            try ThreadRecord.fetchOne(dbConn, key: ["account_id": "acc1", "id": "t1"])
        }
        #expect(syncedThread != nil)
        #expect(syncedThread?.messageCount == 1)

        let indexed = try db.read { dbConn in
            try MailSearchDocumentRecord.fetchOne(
                dbConn,
                sql: "SELECT * FROM mail_search_document WHERE account_id = ? AND message_id = ?",
                arguments: ["acc1", "m1"]
            )
        }
        #expect(indexed?.snippet == "canonical snippet from Gmail")
        #expect(indexed?.isSent == 1)
        #expect(indexed?.canonicalMailboxes == "SENT")
    }
}

private func setHistoryId(_ historyId: String, db: AppDatabase) async throws {
    try await DatabaseActor.shared.run {
        try db.write { dbConn in
            var syncState = try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])!
            syncState.historyId = historyId
            try syncState.update(dbConn)
        }
    }
}

private func seedThreadWithAttachmentArtifacts(
    _ db: AppDatabase,
    threadId: String,
    messageId: String,
    attachmentIds: [String]
) async throws {
    try await DatabaseActor.shared.run {
        try db.write { dbConn in
            try ThreadRecord(
                id: threadId,
                accountId: "acc1",
                subject: "Subject",
                lastMessageAt: 1000,
                messageCount: 1
            ).insert(dbConn)
            try MessageRecord(
                id: messageId,
                threadId: threadId,
                accountId: "acc1",
                sentAt: 1000
            ).insert(dbConn)

            for attachmentId in attachmentIds {
                try AttachmentRecord(
                    id: attachmentId,
                    messageId: messageId,
                    accountId: "acc1",
                    filename: "\(attachmentId).pdf",
                    mime: "application/pdf",
                    sizeBytes: 42
                ).insert(dbConn)
                try AttachmentBlobRecord(
                    accountId: "acc1",
                    messageId: messageId,
                    attachmentId: attachmentId,
                    relativePath: "attachments/\(attachmentId).pdf",
                    byteCount: 42,
                    sha256: "sha-\(attachmentId)",
                    storedAt: 1000
                ).insert(dbConn)
                try AttachmentExtractionRecord(
                    accountId: "acc1",
                    messageId: messageId,
                    attachmentId: attachmentId,
                    extractionVersion: "pdf-text.v1",
                    status: "completed",
                    contentHash: "hash-\(attachmentId)",
                    mime: "application/pdf",
                    filename: "\(attachmentId).pdf",
                    byteCount: 42,
                    createdAt: 1000,
                    updatedAt: 1000,
                    completedAt: 1000,
                    errorCode: nil,
                    errorMessage: nil
                ).insert(dbConn)
                try AttachmentChunkRecord(
                    accountId: "acc1",
                    messageId: messageId,
                    attachmentId: attachmentId,
                    extractionVersion: "pdf-text.v1",
                    chunkIndex: 0,
                    contentText: "Grounded attachment text for \(attachmentId).",
                    createdAt: 1000
                ).insert(dbConn)
                try AttachmentAIArtifactRecord(
                    accountId: "acc1",
                    messageId: messageId,
                    attachmentId: attachmentId,
                    extractionVersion: "pdf-text.v1",
                    artifactKind: "attachmentSummary",
                    artifactVersion: 1,
                    modelId: "local-test-model",
                    contentHash: "hash-\(attachmentId)",
                    payloadJSON: "{}",
                    createdAt: 1000,
                    updatedAt: 1000
                ).insert(dbConn)
            }
        }
    }
}

private func artifactCounts(
    _ db: AppDatabase,
    attachmentId: String
) async throws -> (blobs: Int, extractions: Int, chunks: Int, artifacts: Int) {
    try await DatabaseActor.shared.run {
        try db.read { dbConn in
            let blobCount = try AttachmentBlobRecord
                .filter(Column("attachment_id") == attachmentId)
                .fetchCount(dbConn)
            let extractionCount = try AttachmentExtractionRecord
                .filter(Column("attachment_id") == attachmentId)
                .fetchCount(dbConn)
            let chunkCount = try AttachmentChunkRecord
                .filter(Column("attachment_id") == attachmentId)
                .fetchCount(dbConn)
            let artifactCount = try AttachmentAIArtifactRecord
                .filter(Column("attachment_id") == attachmentId)
                .fetchCount(dbConn)
            return (blobCount, extractionCount, chunkCount, artifactCount)
        }
    }
}

// Helper to run code on DatabaseActor
extension DatabaseActor {
    func run<T: Sendable>(_ block: @DatabaseActor @Sendable () throws -> T) async throws -> T {
        try await block()
    }
}
