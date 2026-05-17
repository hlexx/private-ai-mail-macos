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
}
