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

        let thread = try db.read { dbConn in
            try ThreadRecord.filter(Column("id") == "thread_888" && Column("account_id") == "acc_1").fetchOne(dbConn)
        }
        #expect(thread != nil)
        #expect(thread?.subject == "Test Subject")
        #expect(thread?.messageCount == 1)
    }

    @Test func replyDoesNotInsertNewThread() async throws {
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
        let reply = ReplyContext(threadID: "existing_thread", inReplyToMessageID: "<orig@example.com>", referencesChain: ["<orig@example.com>"])
        let draft = makeDraft(replyContext: reply)

        let echo = try await service.send(draft)

        #expect(echo.threadID == "existing_thread")
        #expect(mockAPI.lastThreadId == "existing_thread")

        let threadCount = try db.read { dbConn in
            try ThreadRecord.filter(Column("id") == "existing_thread").fetchCount(dbConn)
        }
        #expect(threadCount == 1)
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

    @Test func genericAPIErrorWrapsAsSendError() async throws {
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
    }
}

extension DatabaseActor {
    func run<T: Sendable>(_ body: @DatabaseActor @Sendable () throws -> T) async rethrows -> T {
        try await body()
    }
}
