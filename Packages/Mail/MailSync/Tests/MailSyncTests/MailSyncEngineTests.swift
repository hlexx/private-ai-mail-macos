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

    private func makeThread(
        id: String,
        messageIds: [String],
        attachmentIdsByMessage: [String: [String]] = [:]
    ) -> GmailDTO.Thread {
        let messages = messageIds.map { msgId in
            let attachmentParts = (attachmentIdsByMessage[msgId] ?? []).map { attachmentId in
                GmailDTO.MessagePart(
                    partId: attachmentId,
                    mimeType: "application/pdf",
                    filename: "\(attachmentId).pdf",
                    body: GmailDTO.MessagePartBody(attachmentId: attachmentId, size: 128)
                )
            }
            return GmailDTO.Message(
                id: msgId,
                threadId: id,
                labelIds: ["INBOX"],
                snippet: "snippet-\(msgId)",
                historyId: "100",
                internalDate: "\(Int(Date().timeIntervalSince1970 * 1000))",
                payload: GmailDTO.MessagePart(
                    mimeType: "multipart/mixed",
                    headers: [
                        GmailDTO.MessagePartHeader(name: "Subject", value: "Test subject \(id)"),
                        GmailDTO.MessagePartHeader(name: "From", value: "sender@example.com"),
                    ],
                    parts: attachmentParts.isEmpty ? nil : attachmentParts
                )
            )
        }
        return GmailDTO.Thread(id: id, historyId: "100", messages: messages)
    }

    private func seedAttachmentArtifacts(
        _ dbConn: Database,
        accountId: String = "acc1",
        messageId: String,
        attachmentId: String
    ) throws {
        try AttachmentRecord(
            id: attachmentId,
            messageId: messageId,
            accountId: accountId,
            filename: "\(attachmentId).pdf",
            mime: "application/pdf",
            sizeBytes: 128
        ).insert(dbConn)
        try AttachmentBlobRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            relativePath: "\(accountId)/\(messageId)/\(attachmentId)",
            byteCount: 128,
            sha256: "sha-\(attachmentId)",
            storedAt: 1
        ).insert(dbConn)
        try AttachmentExtractionRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            status: "extracted",
            contentHash: "sha-\(attachmentId)",
            mime: "application/pdf",
            filename: "\(attachmentId).pdf",
            byteCount: 128,
            createdAt: 1,
            updatedAt: 1,
            completedAt: 1,
            errorCode: nil,
            errorMessage: nil
        ).insert(dbConn)
        try AttachmentChunkRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            chunkIndex: 0,
            contentText: "Synthetic chunk for \(attachmentId)",
            sourceStart: 0,
            sourceEnd: 20,
            tokenCount: 4,
            createdAt: 1
        ).insert(dbConn)
        try AttachmentAIArtifactRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId,
            extractionVersion: "v1",
            artifactKind: "attachmentSummary:attachment-summary.v1:attachment-summary.schema.v1",
            artifactVersion: 1,
            modelId: "local-test",
            contentHash: "sha-\(attachmentId)",
            payloadJSON: #"{"summary":"Synthetic"}"#,
            createdAt: 1,
            updatedAt: 1
        ).insert(dbConn)
    }

    private func artifactCounts(_ dbConn: Database, attachmentId: String) throws -> [String: Int] {
        [
            "attachments": try AttachmentRecord
                .filter(Column("account_id") == "acc1" && Column("id") == attachmentId)
                .fetchCount(dbConn),
            "blobs": try AttachmentBlobRecord
                .filter(Column("account_id") == "acc1" && Column("attachment_id") == attachmentId)
                .fetchCount(dbConn),
            "extractions": try AttachmentExtractionRecord
                .filter(Column("account_id") == "acc1" && Column("attachment_id") == attachmentId)
                .fetchCount(dbConn),
            "chunks": try AttachmentChunkRecord
                .filter(Column("account_id") == "acc1" && Column("attachment_id") == attachmentId)
                .fetchCount(dbConn),
            "aiArtifacts": try AttachmentAIArtifactRecord
                .filter(Column("account_id") == "acc1" && Column("attachment_id") == attachmentId)
                .fetchCount(dbConn),
        ]
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

    @Test func incrementalSyncUsesOriginalHistoryIdAcrossPagesAndUpdatesAfterFinalPage() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        try await DatabaseActor.shared.run {
            try db.write { dbConn in
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
                                message: GmailDTO.Message(id: "m1", threadId: "t1")
                            )
                        ]
                    )
                ],
                nextPageToken: "page-2",
                historyId: "60"
            )),
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "61",
                        messagesAdded: [
                            GmailDTO.HistoryMessageAdded(
                                message: GmailDTO.Message(id: "m2", threadId: "t2")
                            )
                        ]
                    )
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

        #expect(api.listHistoryCalls.count == 2)
        #expect(api.listHistoryCalls[0].startHistoryId == "50")
        #expect(api.listHistoryCalls[0].pageToken == nil)
        #expect(api.listHistoryCalls[1].startHistoryId == "50")
        #expect(api.listHistoryCalls[1].pageToken == "page-2")

        let syncState = try db.read { dbConn in
            try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])
        }
        #expect(syncState?.historyId == "70")

        let messageIds = try db.read { dbConn in
            try MessageRecord
                .filter(Column("account_id") == "acc1")
                .fetchAll(dbConn)
                .map(\.id)
                .sorted()
        }
        #expect(messageIds == ["m1", "m2"])
    }

    @Test func incrementalSyncDoesNotUseIntermediateHistoryIdForNextPage() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        try await DatabaseActor.shared.run {
            try db.write { dbConn in
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
                        labelsAdded: [
                            GmailDTO.HistoryLabelAdded(
                                message: GmailDTO.Message(id: "m1", threadId: "t1"),
                                labelIds: ["STARRED"]
                            )
                        ]
                    )
                ],
                nextPageToken: "page-2",
                historyId: "999"
            )),
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "52",
                        labelsRemoved: [
                            GmailDTO.HistoryLabelRemoved(
                                message: GmailDTO.Message(id: "m1", threadId: "t1"),
                                labelIds: ["STARRED"]
                            )
                        ]
                    )
                ],
                nextPageToken: nil,
                historyId: "1000"
            )),
        ]
        api.getThreadResults = [
            "t1": .success(makeThread(id: "t1", messageIds: ["m1"])),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        #expect(api.listHistoryCalls.map(\.startHistoryId) == ["50", "50"])
        #expect(api.listHistoryCalls.map(\.pageToken) == [nil, "page-2"])

        let syncState = try db.read { dbConn in
            try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])
        }
        #expect(syncState?.historyId == "1000")
    }

    @Test func incrementalSyncKeepsOriginalCheckpointWhenLaterHistoryPageFails() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        try await DatabaseActor.shared.run {
            try db.write { dbConn in
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
                                message: GmailDTO.Message(id: "m1", threadId: "t1")
                            )
                        ]
                    )
                ],
                nextPageToken: "page-2",
                historyId: "999"
            )),
            .failure(GmailAPIError.serverError(statusCode: 500)),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        let stream = await engine.makeEventStream()
        let eventTask = Task {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        await engine.refresh()

        #expect(api.listHistoryCalls.map(\.startHistoryId) == ["50", "50"])
        #expect(api.listHistoryCalls.map(\.pageToken) == [nil, "page-2"])

        let syncState = try db.read { dbConn in
            try SyncStateRecord.fetchOne(dbConn, key: ["account_id": "acc1"])
        }
        #expect(syncState?.historyId == "50")

        guard case .error(.incrementalFailed(let error)) = await eventTask.value else {
            Issue.record("Expected incremental failure event")
            return
        }
        guard let gmailError = error as? GmailAPIError,
              case .serverError(statusCode: 500) = gmailError else {
            Issue.record("Expected page failure to surface as Gmail server error")
            return
        }
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
    }

    @Test func incrementalLabelRefreshPreservesAttachmentArtifacts() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try ThreadRecord(
                    id: "t1",
                    accountId: "acc1",
                    subject: "Subject",
                    lastMessageAt: 1000,
                    messageCount: 1
                ).insert(dbConn)
                try MessageRecord(id: "m1", threadId: "t1", accountId: "acc1", sentAt: 1000).insert(dbConn)
                try seedAttachmentArtifacts(dbConn, messageId: "m1", attachmentId: "att1")

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
                        labelsAdded: [
                            GmailDTO.HistoryLabelAdded(
                                message: GmailDTO.Message(id: "m1", threadId: "t1"),
                                labelIds: ["STARRED"]
                            )
                        ]
                    )
                ],
                nextPageToken: nil,
                historyId: "60"
            )),
        ]
        api.getThreadResults = [
            "t1": .success(makeThread(
                id: "t1",
                messageIds: ["m1"],
                attachmentIdsByMessage: ["m1": ["att1"]]
            )),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        let counts = try db.read { dbConn in
            try artifactCounts(dbConn, attachmentId: "att1")
        }

        #expect(counts["attachments"] == 1)
        #expect(counts["blobs"] == 1)
        #expect(counts["extractions"] == 1)
        #expect(counts["chunks"] == 1)
        #expect(counts["aiArtifacts"] == 1)
    }

    @Test func incrementalRefreshDeletesArtifactsOnlyForRemovedAttachment() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try ThreadRecord(
                    id: "t1",
                    accountId: "acc1",
                    subject: "Subject",
                    lastMessageAt: 1000,
                    messageCount: 1
                ).insert(dbConn)
                try MessageRecord(id: "m1", threadId: "t1", accountId: "acc1", sentAt: 1000).insert(dbConn)
                try seedAttachmentArtifacts(dbConn, messageId: "m1", attachmentId: "att1")
                try seedAttachmentArtifacts(dbConn, messageId: "m1", attachmentId: "att2")

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
                                message: GmailDTO.Message(id: "m1", threadId: "t1")
                            )
                        ]
                    )
                ],
                nextPageToken: nil,
                historyId: "60"
            )),
        ]
        api.getThreadResults = [
            "t1": .success(makeThread(
                id: "t1",
                messageIds: ["m1"],
                attachmentIdsByMessage: ["m1": ["att1"]]
            )),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        let keptCounts = try db.read { dbConn in
            try artifactCounts(dbConn, attachmentId: "att1")
        }
        let removedCounts = try db.read { dbConn in
            try artifactCounts(dbConn, attachmentId: "att2")
        }

        #expect(keptCounts["attachments"] == 1)
        #expect(keptCounts["blobs"] == 1)
        #expect(keptCounts["extractions"] == 1)
        #expect(keptCounts["chunks"] == 1)
        #expect(keptCounts["aiArtifacts"] == 1)
        #expect(removedCounts["attachments"] == 0)
        #expect(removedCounts["blobs"] == 0)
        #expect(removedCounts["extractions"] == 0)
        #expect(removedCounts["chunks"] == 0)
        #expect(removedCounts["aiArtifacts"] == 0)
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

    @Test func reBootstrapIsIdempotent() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        let api = MockGmailAPI()
        let threadDTO = makeThread(
            id: "t1",
            messageIds: ["m1", "m2"],
            attachmentIdsByMessage: [
                "m1": ["att1"],
                "m2": ["att2"],
            ]
        )

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
        let attachmentCountAfterFirst = try db.read { dbConn in
            try AttachmentRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }

        let getThreadCallsAfterFirst = api.getThreadCalled

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
        api.resetListMessagesCallIndex()

        let engine2 = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine2.bootstrap()

        let countAfterSecond = try db.read { dbConn in
            try ThreadRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        let msgCountAfterSecond = try db.read { dbConn in
            try MessageRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        let attachmentCountAfterSecond = try db.read { dbConn in
            try AttachmentRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }

        #expect(countAfterFirst == countAfterSecond)
        #expect(msgCountAfterFirst == msgCountAfterSecond)
        #expect(attachmentCountAfterFirst == attachmentCountAfterSecond)
        #expect(countAfterSecond == 1)
        #expect(msgCountAfterSecond == 2)
        #expect(attachmentCountAfterSecond == 2)
        #expect(api.getThreadCalled == getThreadCallsAfterFirst + 1)
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
    }
}

// Helper to run code on DatabaseActor
extension DatabaseActor {
    func run<T: Sendable>(_ block: @DatabaseActor @Sendable () throws -> T) async throws -> T {
        try await block()
    }
}
