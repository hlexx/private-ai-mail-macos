import Testing
import Foundation
@testable import InboxFeature
@testable import ThreadFeature
import Persistence
import GRDB

@Suite("InboxUI")
struct InboxUITests {

    private func seedDatabase() throws -> AppDatabase {
        let db = try AppDatabase.openInMemorySync()

        let accountId = "acc-1"
        let account = AccountRecord(
            id: accountId,
            provider: "gmail",
            email: "test@gmail.com",
            displayName: "Test User",
            createdAt: Int(Date.now.timeIntervalSince1970)
        )
        try db.dbQueue.write { dbConn in
            try account.insert(dbConn)
        }

        let now = Int(Date.now.timeIntervalSince1970)

        let thread1 = ThreadRecord(
            id: "thread-1",
            accountId: accountId,
            subject: "Hello World",
            snippet: "This is the first thread",
            lastMessageAt: now - 3600,
            messageCount: 2,
            hasUnread: 1
        )
        let thread2 = ThreadRecord(
            id: "thread-2",
            accountId: accountId,
            subject: "Meeting Notes",
            snippet: "Attached are the meeting notes",
            lastMessageAt: now,
            messageCount: 1,
            hasUnread: 0
        )

        let msg1 = MessageRecord(
            id: "msg-1",
            threadId: "thread-1",
            accountId: accountId,
            fromAddr: "alice@example.com",
            sentAt: now - 7200,
            snippet: "Hi, how are you?"
        )
        let msg2 = MessageRecord(
            id: "msg-2",
            threadId: "thread-1",
            accountId: accountId,
            fromAddr: "bob@example.com",
            sentAt: now - 3600,
            snippet: "I am fine, thanks!"
        )
        let msg3 = MessageRecord(
            id: "msg-3",
            threadId: "thread-2",
            accountId: accountId,
            fromAddr: "carol@example.com",
            sentAt: now,
            snippet: "Please review the attached notes."
        )

        try db.dbQueue.write { dbConn in
            try thread1.insert(dbConn)
            try thread2.insert(dbConn)
            try LabelRecord(id: "INBOX", accountId: accountId, name: "Inbox", type: .system)
                .insert(dbConn)
            try ThreadLabelRecord(accountId: accountId, threadId: thread1.id, labelId: "INBOX")
                .insert(dbConn)
            try ThreadLabelRecord(accountId: accountId, threadId: thread2.id, labelId: "INBOX")
                .insert(dbConn)
            try msg1.insert(dbConn)
            try msg2.insert(dbConn)
            try msg3.insert(dbConn)
        }

        return db
    }

    @Test @MainActor func inboxStoreLoadsThreads() async throws {
        let db = try seedDatabase()
        let store = InboxStore(db: db)
        store.startObserving()

        // Give ValueObservation time to deliver initial value
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.threads.count == 2)
        let first = try #require(store.threads.first)
        let second = try #require(store.threads.dropFirst().first)
        // Sorted by last_message_at DESC: thread-2 first, thread-1 second
        #expect(first.subject == "Meeting Notes")
        #expect(second.subject == "Hello World")
        #expect(first.snippet == "Attached are the meeting notes")
        #expect(second.hasUnread == true)
        #expect(second.messageCount == 2)

        store.stopObserving()
    }

    @Test @MainActor func threadStoreLoadsMessages() async throws {
        let db = try seedDatabase()
        let store = ThreadStore(db: db)
        store.observe(threadId: "thread-1", accountId: "acc-1")

        try await Task.sleep(for: .milliseconds(200))

        #expect(store.messages.count == 2)
        let first = try #require(store.messages.first)
        let second = try #require(store.messages.dropFirst().first)
        // Sorted by sent_at ASC
        #expect(first.fromAddr == "alice@example.com")
        #expect(second.fromAddr == "bob@example.com")

        store.stopObserving()
    }

    @Test @MainActor func selectingThreadUpdatesThreadStore() async throws {
        let db = try seedDatabase()
        let inboxStore = InboxStore(db: db)
        let threadStore = ThreadStore(db: db)
        inboxStore.startObserving()

        try await Task.sleep(for: .milliseconds(200))
        #expect(inboxStore.threads.count == 2)

        // Simulate selecting thread-1
        let selected = try #require(inboxStore.threads.first { $0.id == "thread-1" })
        threadStore.observe(threadId: selected.id, accountId: selected.accountId)

        try await Task.sleep(for: .milliseconds(200))
        #expect(threadStore.messages.count == 2)

        inboxStore.stopObserving()
        threadStore.stopObserving()
    }

    @Test func accountRecordsAreFetchable() throws {
        let db = try seedDatabase()
        let accounts = try db.dbQueue.read { dbConn in
            try AccountRecord.fetchAll(dbConn)
        }
        #expect(accounts.count == 1)
        #expect(accounts[0].email == "test@gmail.com")
    }
}
