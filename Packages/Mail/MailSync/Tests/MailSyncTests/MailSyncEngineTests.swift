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
        let messages = messageIds.map { msgId in
            GmailDTO.Message(
                id: msgId,
                threadId: id,
                labelIds: ["INBOX"],
                snippet: "snippet-\(msgId)",
                historyId: "100",
                internalDate: "\(Int(Date().timeIntervalSince1970 * 1000))",
                payload: GmailDTO.MessagePart(
                    headers: [
                        GmailDTO.MessagePartHeader(name: "Subject", value: "Test subject \(id)"),
                        GmailDTO.MessagePartHeader(name: "From", value: "sender@example.com"),
                    ]
                )
            )
        }
        return GmailDTO.Thread(id: id, historyId: "100", messages: messages)
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

        #expect(countAfterFirst == countAfterSecond)
        #expect(msgCountAfterFirst == msgCountAfterSecond)
        #expect(countAfterSecond == 1)
        #expect(msgCountAfterSecond == 2)
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
