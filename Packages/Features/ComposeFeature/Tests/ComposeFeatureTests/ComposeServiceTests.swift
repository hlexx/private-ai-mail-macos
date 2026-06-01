import Foundation
import GRDB
import MailDomain
import MailProviders
import Persistence
import Testing
@testable import ComposeFeature

@Suite("ComposeService")
struct ComposeServiceTests {

    private func makeDB() async throws -> AppDatabase {
        try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
    }

    private func seedAccount(db: AppDatabase, id: String = "acc_1", email: String = "me@gmail.com") async throws {
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try AccountRecord(id: id, email: email, createdAt: 1000).insert(dbConn)
            }
        }
    }

    private func makeDraft(
        accountID: String = "acc_1",
        to: [Address] = [Address(name: "Bob", email: "bob@example.com")],
        replyContext: ReplyContext? = nil
    ) -> ComposeDraft {
        ComposeDraft(
            accountID: accountID,
            from: Address(name: "Me", email: "me@gmail.com"),
            to: to,
            subject: "Test Subject",
            body: "Hello, world!",
            replyContext: replyContext
        )
    }

    @Test func happyPathSendInsertsRowAndReturnsSentEcho() async throws {
        let db = try await makeDB()
        try await seedAccount(db: db)

        let mockAPI = MockGmailAPI()
        mockAPI.sendMessageResult = .success(
            GmailDTO.SentMessage(id: "msg_999", threadId: "thread_888", labelIds: ["SENT"])
        )

        let service = LiveComposeService(api: mockAPI, db: db)
        let draft = makeDraft()

        let echo = try await service.send(draft)

        #expect(echo.messageID == "msg_999")
        #expect(echo.threadID == "thread_888")
        #expect(mockAPI.sendCallCount == 1)
        #expect(mockAPI.lastThreadId == nil)

        let msg = try db.read { dbConn in
            try MessageRecord.filter(Column("id") == "msg_999" && Column("account_id") == "acc_1").fetchOne(dbConn)
        }
        #expect(msg != nil)
        #expect(msg?.threadId == "thread_888")
        #expect(msg?.accountId == "acc_1")
        #expect(msg?.flags == MessageRecord.sentByMe | MessageRecord.read)
        #expect(msg?.bodyText == "Hello, world!")

        let hasSentLabel = try db.read { dbConn in
            try ThreadLabelRecord
                .filter(Column("account_id") == "acc_1" && Column("thread_id") == "thread_888" && Column("label_id") == "SENT")
                .fetchCount(dbConn)
        }
        #expect(hasSentLabel == 1)

        let thread = try db.read { dbConn in
            try ThreadRecord.filter(Column("id") == "thread_888" && Column("account_id") == "acc_1").fetchOne(dbConn)
        }
        #expect(thread != nil)
        #expect(thread?.subject == "Test Subject")
        #expect(thread?.messageCount == 1)
    }

    @Test func replySendPassesThreadIdAndBuildsReplyHeaders() async throws {
        let db = try await makeDB()
        try await seedAccount(db: db)

        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try ThreadRecord(id: "existing_thread", accountId: "acc_1", lastMessageAt: 500, messageCount: 2).insert(dbConn)
            }
        }

        let mockAPI = MockGmailAPI()
        mockAPI.sendMessageResult = .success(
            GmailDTO.SentMessage(id: "reply_1", threadId: "existing_thread", labelIds: ["SENT"])
        )

        let service = LiveComposeService(api: mockAPI, db: db)
        let reply = ReplyContext(threadID: "existing_thread", inReplyToMessageID: "<orig@example.com>", referencesChain: ["<root@example.com>"])
        let draft = makeDraft(replyContext: reply)

        let echo = try await service.send(draft)

        #expect(echo.threadID == "existing_thread")
        #expect(mockAPI.lastThreadId == "existing_thread")
        let raw = try #require(decodedRawMessage(from: mockAPI))
        #expect(raw.contains("In-Reply-To: <orig@example.com>\r\n"))
        #expect(raw.contains("References: <root@example.com> <orig@example.com>\r\n"))

        let threadCount = try db.read { dbConn in
            try ThreadRecord.filter(Column("id") == "existing_thread").fetchCount(dbConn)
        }
        #expect(threadCount == 1)

        let thread = try db.read { dbConn in
            try ThreadRecord.fetchOne(dbConn, key: ["account_id": "acc_1", "id": "existing_thread"])
        }
        #expect(thread?.messageCount == 3)
    }

    @Test func insufficientScopeThrowsNeedsReconsent() async throws {
        let db = try await makeDB()
        try await seedAccount(db: db)

        let mockAPI = MockGmailAPI()
        mockAPI.sendMessageResult = .failure(GmailAPIError.insufficientScope)

        let service = LiveComposeService(api: mockAPI, db: db)
        let draft = makeDraft()

        do {
            _ = try await service.send(draft)
            Issue.record("Expected ComposeError.needsReconsent")
        } catch let error as ComposeError {
            if case .needsReconsent = error {
                // expected
            } else {
                Issue.record("Expected needsReconsent, got \(error)")
            }
        }
        let messageCount = try db.read { dbConn in
            try MessageRecord.filter(Column("account_id") == "acc_1").fetchCount(dbConn)
        }
        #expect(messageCount == 0)
    }

    @Test func emptyRecipientsThrowsNoRecipients() async throws {
        let db = try await makeDB()
        let mockAPI = MockGmailAPI()
        let service = LiveComposeService(api: mockAPI, db: db)
        let draft = makeDraft(to: [])

        do {
            _ = try await service.send(draft)
            Issue.record("Expected ComposeError.noRecipients")
        } catch let error as ComposeError {
            if case .noRecipients = error {
                // expected
            } else {
                Issue.record("Expected noRecipients, got \(error)")
            }
        }

        #expect(mockAPI.sendCallCount == 0)
    }

    @Test func genericAPIErrorWrapsAsSendErrorAndDoesNotInsertLocalSentState() async throws {
        let db = try await makeDB()
        try await seedAccount(db: db)

        let mockAPI = MockGmailAPI()
        mockAPI.sendMessageResult = .failure(GmailAPIError.serverError(statusCode: 500))

        let service = LiveComposeService(api: mockAPI, db: db)
        let draft = makeDraft()

        do {
            _ = try await service.send(draft)
            Issue.record("Expected ComposeError.send")
        } catch let error as ComposeError {
            if case .send(let underlying) = error {
                #expect(underlying is GmailAPIError)
            } else {
                Issue.record("Expected send(underlying:), got \(error)")
            }
        }

        let localState = try db.read { dbConn in
            let messages = try MessageRecord.filter(Column("account_id") == "acc_1").fetchCount(dbConn)
            let threads = try ThreadRecord.filter(Column("account_id") == "acc_1").fetchCount(dbConn)
            let labels = try ThreadLabelRecord.filter(Column("account_id") == "acc_1").fetchCount(dbConn)
            return (messages: messages, threads: threads, labels: labels)
        }
        #expect(localState.messages == 0)
        #expect(localState.threads == 0)
        #expect(localState.labels == 0)
    }

    @Test func duplicateReturnedSentMessageDoesNotDuplicateLocalRowsOrThreadCount() async throws {
        let db = try await makeDB()
        try await seedAccount(db: db)

        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try ThreadRecord(
                    id: "existing_thread",
                    accountId: "acc_1",
                    lastMessageAt: 500,
                    messageCount: 2
                ).insert(dbConn)
            }
        }

        let mockAPI = MockGmailAPI()
        mockAPI.sendMessageResult = .success(
            GmailDTO.SentMessage(id: "reply_1", threadId: "existing_thread", labelIds: ["SENT"])
        )

        let service = LiveComposeService(api: mockAPI, db: db)
        let reply = ReplyContext(
            threadID: "existing_thread",
            inReplyToMessageID: "<orig@example.com>",
            referencesChain: ["<root@example.com>", "<orig@example.com>"]
        )
        let draft = makeDraft(replyContext: reply)

        _ = try await service.send(draft)
        _ = try await service.send(draft)

        let state = try db.read { dbConn in
            let messages = try MessageRecord
                .filter(Column("account_id") == "acc_1" && Column("id") == "reply_1")
                .fetchCount(dbConn)
            let thread = try ThreadRecord.fetchOne(dbConn, key: ["account_id": "acc_1", "id": "existing_thread"])
            let labels = try ThreadLabelRecord
                .filter(Column("account_id") == "acc_1" && Column("thread_id") == "existing_thread" && Column("label_id") == "SENT")
                .fetchCount(dbConn)
            return (messages: messages, thread: thread, labels: labels)
        }
        #expect(state.messages == 1)
        #expect(state.thread?.messageCount == 3)
        #expect(state.labels == 1)
    }
}

private func decodedRawMessage(from api: MockGmailAPI) -> String? {
    guard var base64 = api.lastRaw else { return nil }
    base64 = base64
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder > 0 {
        base64 += String(repeating: "=", count: 4 - remainder)
    }
    guard let data = Data(base64Encoded: base64) else { return nil }
    return String(data: data, encoding: .utf8)
}

extension DatabaseActor {
    func run<T: Sendable>(_ body: @DatabaseActor @Sendable () throws -> T) async rethrows -> T {
        try await body()
    }
}
