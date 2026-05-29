import Testing
import Foundation
@testable import MailSync
import MailProviders
import Persistence
import GRDB

@Suite("LabelRoundTrip")
struct LabelRoundTripTests {

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

    private func messageDTO(
        id: String,
        threadId: String,
        labelIds: [String],
        historyId: String,
        attachmentId: String? = nil
    ) -> GmailDTO.Message {
        let attachmentPart: GmailDTO.MessagePart? = attachmentId.map {
            GmailDTO.MessagePart(
                partId: "1",
                mimeType: "application/pdf",
                filename: "contract.pdf",
                body: GmailDTO.MessagePartBody(attachmentId: $0, size: 2048)
            )
        }
        return GmailDTO.Message(
            id: id,
            threadId: threadId,
            labelIds: labelIds,
            snippet: "hello",
            historyId: historyId,
            internalDate: "\(Int(Date().timeIntervalSince1970 * 1000))",
            payload: GmailDTO.MessagePart(
                headers: [
                    GmailDTO.MessagePartHeader(name: "Subject", value: "Test"),
                    GmailDTO.MessagePartHeader(name: "From", value: "sender@example.com"),
                ],
                parts: attachmentPart.map { [$0] }
            )
        )
    }

    @Test func bootstrapSyncsLabelsAndThreadLabels() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        let api = MockGmailAPI()
        api.listLabelsResult = .success([
            GmailDTO.Label(id: "INBOX", name: "INBOX", type: "system"),
            GmailDTO.Label(id: "STARRED", name: "STARRED", type: "system"),
            GmailDTO.Label(id: "Label_x", name: "My Label", type: "user"),
        ])

        let threadDTO = GmailDTO.Thread(
            id: "t1",
            historyId: "100",
            messages: [
                GmailDTO.Message(
                    id: "m1",
                    threadId: "t1",
                    labelIds: ["INBOX", "STARRED", "Label_x"],
                    snippet: "hello",
                    historyId: "100",
                    internalDate: "\(Int(Date().timeIntervalSince1970 * 1000))",
                    payload: GmailDTO.MessagePart(
                        headers: [
                            GmailDTO.MessagePartHeader(name: "Subject", value: "Test"),
                            GmailDTO.MessagePartHeader(name: "From", value: "sender@example.com"),
                        ]
                    )
                )
            ]
        )

        api.listMessagesResults = [
            .success(GmailDTO.MessageList(
                messages: [GmailDTO.MessageRef(id: "m1", threadId: "t1")],
                nextPageToken: nil
            ))
        ]
        api.getThreadResults = ["t1": .success(threadDTO)]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.bootstrap()

        // Verify labels were created
        let labelCount = try db.read { dbConn in
            try LabelRecord.filter(Column("account_id") == "acc1").fetchCount(dbConn)
        }
        #expect(labelCount == 3)

        // Verify thread_label rows
        let threadLabelCount = try db.read { dbConn in
            try ThreadLabelRecord.filter(Column("thread_id") == "t1").fetchCount(dbConn)
        }
        #expect(threadLabelCount == 3)

        // Verify specific labels exist
        let labelIds = try db.read { dbConn in
            try ThreadLabelRecord
                .filter(Column("thread_id") == "t1")
                .fetchAll(dbConn)
                .map(\.labelId)
                .sorted()
        }
        #expect(labelIds == ["INBOX", "Label_x", "STARRED"])
    }

    @Test func incrementalSyncUpdatesThreadLabels() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        let api = MockGmailAPI()
        api.listLabelsResult = .success([
            GmailDTO.Label(id: "INBOX", name: "INBOX", type: "system"),
            GmailDTO.Label(id: "STARRED", name: "STARRED", type: "system"),
            GmailDTO.Label(id: "Label_x", name: "My Label", type: "user"),
        ])

        // First bootstrap with INBOX + STARRED + Label_x
        let threadDTO1 = GmailDTO.Thread(
            id: "t1",
            historyId: "100",
            messages: [
                GmailDTO.Message(
                    id: "m1",
                    threadId: "t1",
                    labelIds: ["INBOX", "STARRED", "Label_x"],
                    snippet: "hello",
                    historyId: "100",
                    internalDate: "\(Int(Date().timeIntervalSince1970 * 1000))",
                    payload: GmailDTO.MessagePart(
                        headers: [
                            GmailDTO.MessagePartHeader(name: "Subject", value: "Test"),
                            GmailDTO.MessagePartHeader(name: "From", value: "sender@example.com"),
                        ]
                    )
                )
            ]
        )
        api.listMessagesResults = [
            .success(GmailDTO.MessageList(
                messages: [GmailDTO.MessageRef(id: "m1", threadId: "t1")],
                nextPageToken: nil
            ))
        ]
        api.getThreadResults = ["t1": .success(threadDTO1)]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.bootstrap()

        // Verify 3 thread_label rows
        let count1 = try db.read { dbConn in
            try ThreadLabelRecord.filter(Column("thread_id") == "t1").fetchCount(dbConn)
        }
        #expect(count1 == 3)

        // Now simulate incremental sync where STARRED is removed
        let threadDTO2 = GmailDTO.Thread(
            id: "t1",
            historyId: "110",
            messages: [
                GmailDTO.Message(
                    id: "m1",
                    threadId: "t1",
                    labelIds: ["INBOX", "Label_x"],
                    snippet: "hello",
                    historyId: "110",
                    internalDate: "\(Int(Date().timeIntervalSince1970 * 1000))",
                    payload: GmailDTO.MessagePart(
                        headers: [
                            GmailDTO.MessagePartHeader(name: "Subject", value: "Test"),
                            GmailDTO.MessagePartHeader(name: "From", value: "sender@example.com"),
                        ]
                    )
                )
            ]
        )

        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "101",
                        labelsRemoved: [
                            GmailDTO.HistoryLabelRemoved(
                                message: GmailDTO.Message(id: "m1", threadId: "t1"),
                                labelIds: ["STARRED"]
                            )
                        ]
                    )
                ],
                nextPageToken: nil,
                historyId: "110"
            ))
        ]
        api.getThreadResults = ["t1": .success(threadDTO2)]

        await engine.refresh()

        // Verify only 2 thread_label rows remain
        let count2 = try db.read { dbConn in
            try ThreadLabelRecord.filter(Column("thread_id") == "t1").fetchCount(dbConn)
        }
        #expect(count2 == 2)

        let labelIds = try db.read { dbConn in
            try ThreadLabelRecord
                .filter(Column("thread_id") == "t1")
                .fetchAll(dbConn)
                .map(\.labelId)
                .sorted()
        }
        #expect(labelIds == ["INBOX", "Label_x"])
    }

    @Test func labelTypeMappingIsCorrect() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        let api = MockGmailAPI()
        api.listLabelsResult = .success([
            GmailDTO.Label(id: "INBOX", name: "INBOX", type: "system"),
            GmailDTO.Label(id: "CATEGORY_PROMOTIONS", name: "CATEGORY_PROMOTIONS", type: "system"),
            GmailDTO.Label(id: "Label_123", name: "Work", type: "user"),
        ])
        api.listMessagesResults = [
            .success(GmailDTO.MessageList(messages: nil, nextPageToken: nil))
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.bootstrap()

        let labels = try db.read { dbConn in
            try LabelRecord.filter(Column("account_id") == "acc1").fetchAll(dbConn)
        }

        let labelByID = Dictionary(uniqueKeysWithValues: labels.map { ($0.id, $0) })
        #expect(labelByID["INBOX"]?.type == .system)
        #expect(labelByID["CATEGORY_PROMOTIONS"]?.type == .category)
        #expect(labelByID["Label_123"]?.type == .user)
    }

    @Test func bootstrapKeepsArchivedThreadOutOfInboxLabels() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        let api = MockGmailAPI()
        api.listLabelsResult = .success([
            GmailDTO.Label(id: "INBOX", name: "INBOX", type: "system"),
            GmailDTO.Label(id: "STARRED", name: "STARRED", type: "system"),
        ])
        api.listMessagesResults = [
            .success(GmailDTO.MessageList(
                messages: [
                    GmailDTO.MessageRef(id: "mInbox", threadId: "tInbox"),
                    GmailDTO.MessageRef(id: "mArchived", threadId: "tArchived"),
                ],
                nextPageToken: nil
            ))
        ]
        api.getThreadResults = [
            "tInbox": .success(GmailDTO.Thread(
                id: "tInbox",
                historyId: "100",
                messages: [messageDTO(id: "mInbox", threadId: "tInbox", labelIds: ["INBOX"], historyId: "100")]
            )),
            "tArchived": .success(GmailDTO.Thread(
                id: "tArchived",
                historyId: "101",
                messages: [messageDTO(id: "mArchived", threadId: "tArchived", labelIds: ["STARRED"], historyId: "101")]
            )),
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.bootstrap()

        let inboxThreadIds = try db.read { dbConn in
            try ThreadLabelRecord
                .filter(Column("account_id") == "acc1" && Column("label_id") == "INBOX")
                .fetchAll(dbConn)
                .map(\.threadId)
                .sorted()
        }
        #expect(inboxThreadIds == ["tInbox"])
    }

    @Test func reconcileInboxRemovesArchivedThreadWithoutTouchingOtherLabels() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        try await db.dbQueue.write { dbConn in
            for labelId in ["INBOX", "STARRED"] {
                try LabelRecord(id: labelId, accountId: "acc1", name: labelId, type: .system).insert(dbConn)
            }
            for threadId in ["tInbox", "tArchived"] {
                try ThreadRecord(
                    id: threadId,
                    accountId: "acc1",
                    subject: threadId,
                    snippet: nil,
                    lastMessageAt: 1000,
                    messageCount: 1,
                    hasUnread: 0
                ).insert(dbConn)
                try ThreadLabelRecord(accountId: "acc1", threadId: threadId, labelId: "INBOX").insert(dbConn)
            }
            try ThreadLabelRecord(accountId: "acc1", threadId: "tArchived", labelId: "STARRED").insert(dbConn)
        }

        let api = MockGmailAPI()
        api.listMessagesResults = [
            .success(GmailDTO.MessageList(
                messages: [GmailDTO.MessageRef(id: "mInbox", threadId: "tInbox")],
                nextPageToken: nil
            ))
        ]
        let reconciler = LabelReconciler(db: db, apiFactory: { _ in api })
        try await reconciler.reconcileInbox(accountId: "acc1")

        let labelIdsByThread = try db.read { dbConn in
            let rows = try ThreadLabelRecord
                .filter(Column("account_id") == "acc1")
                .fetchAll(dbConn)
            return Dictionary(grouping: rows, by: \.threadId)
                .mapValues { Set($0.map(\.labelId)) }
        }

        #expect(labelIdsByThread["tInbox"] == Set(["INBOX"]))
        #expect(labelIdsByThread["tArchived"] == Set(["STARRED"]))
    }

    @Test func labelOnlyRefreshPreservesAttachmentAndAIArtifactRows() async throws {
        let db = try await makeDB()
        try await seedAccount(db)

        try await db.dbQueue.write { dbConn in
            try SyncStateRecord(accountId: "acc1", historyId: "100", status: "live")
                .save(dbConn, onConflict: .replace)
            for labelId in ["INBOX", "STARRED"] {
                try LabelRecord(id: labelId, accountId: "acc1", name: labelId, type: .system).insert(dbConn)
            }
            try ThreadRecord(
                id: "t1",
                accountId: "acc1",
                subject: "Test",
                snippet: "hello",
                lastMessageAt: 1000,
                messageCount: 1,
                hasUnread: 0
            ).insert(dbConn)
            try MessageRecord(
                id: "m1",
                threadId: "t1",
                accountId: "acc1",
                messageIdHeader: nil,
                fromAddr: "sender@example.com",
                toAddr: "test@gmail.com",
                ccAddr: nil,
                sentAt: 1000,
                snippet: "hello",
                bodyHtml: nil,
                bodyText: nil,
                flags: 0
            ).insert(dbConn)
            try AttachmentRecord(
                id: "att1",
                messageId: "m1",
                accountId: "acc1",
                filename: "contract.pdf",
                mime: "application/pdf",
                sizeBytes: 2048
            ).insert(dbConn)
            try AttachmentExtractionRecord(
                accountId: "acc1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: "v1",
                status: "completed",
                contentHash: "hash",
                mime: "application/pdf",
                filename: "contract.pdf",
                byteCount: 2048,
                createdAt: 1000,
                updatedAt: 1000,
                completedAt: 1000,
                errorCode: nil,
                errorMessage: nil
            ).insert(dbConn)
            try AttachmentAIArtifactRecord(
                accountId: "acc1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: "v1",
                artifactKind: "summary",
                artifactVersion: 1,
                modelId: "local-model",
                contentHash: "hash",
                payloadJSON: #"{"summary":"ok"}"#,
                createdAt: 1000,
                updatedAt: 1000
            ).insert(dbConn)
            try ThreadLabelRecord(accountId: "acc1", threadId: "t1", labelId: "INBOX").insert(dbConn)
        }

        let api = MockGmailAPI()
        api.listHistoryResults = [
            .success(GmailDTO.HistoryResponse(
                history: [
                    GmailDTO.HistoryRecord(
                        id: "101",
                        labelsAdded: [
                            GmailDTO.HistoryLabelAdded(
                                message: GmailDTO.Message(id: "m1", threadId: "t1"),
                                labelIds: ["STARRED"]
                            )
                        ]
                    )
                ],
                nextPageToken: nil,
                historyId: "101"
            ))
        ]
        api.getThreadResults = [
            "t1": .success(GmailDTO.Thread(
                id: "t1",
                historyId: "101",
                messages: [
                    messageDTO(
                        id: "m1",
                        threadId: "t1",
                        labelIds: ["INBOX", "STARRED"],
                        historyId: "101",
                        attachmentId: "att1"
                    ),
                ]
            ))
        ]

        let engine = MailSyncEngine(accountId: "acc1", api: api, db: db)
        await engine.refresh()

        let counts = try db.read { dbConn in
            let attachmentCount = try AttachmentRecord.fetchCount(dbConn)
            let extractionCount = try AttachmentExtractionRecord.fetchCount(dbConn)
            let artifactCount = try AttachmentAIArtifactRecord.fetchCount(dbConn)
            let threadLabels = try ThreadLabelRecord
                .filter(Column("account_id") == "acc1" && Column("thread_id") == "t1")
                .fetchAll(dbConn)
                .map(\.labelId)
                .sorted()
            return (attachmentCount, extractionCount, artifactCount, threadLabels)
        }

        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
        #expect(counts.2 == 1)
        #expect(counts.3 == ["INBOX", "STARRED"])
    }
}
