import Testing
import Foundation
@testable import MailSync
import MailProviders
import Persistence
import GRDB

@Suite("MailMutator")
struct MailMutatorTests {

    private func makeDB() async throws -> AppDatabase {
        try AppDatabase.openInMemorySync()
    }

    /// Seeds an account, a thread, a message, system labels, and thread_label rows.
    private func seedThreadWithLabels(
        _ db: AppDatabase,
        threadId: String = "t1",
        accountId: String = "acc1",
        activeLabels: [String] = ["INBOX", "STARRED"]
    ) throws {
        // All system labels that mutations may reference
        let allSystemLabels = ["INBOX", "STARRED", "TRASH", "UNREAD", "SENT", "DRAFT", "SPAM"]

        try db.dbQueue.write { dbConn in
            try AccountRecord(
                id: accountId,
                email: "test@gmail.com",
                createdAt: Int(Date().timeIntervalSince1970)
            ).insert(dbConn)

            for label in allSystemLabels {
                try LabelRecord(id: label, accountId: accountId, name: label, type: .system)
                    .insert(dbConn)
            }

            try ThreadRecord(
                id: threadId,
                accountId: accountId,
                subject: "Test",
                lastMessageAt: Int(Date().timeIntervalSince1970),
                messageCount: 1,
                hasUnread: 1
            ).insert(dbConn)

            try MessageRecord(
                id: "m1",
                threadId: threadId,
                accountId: accountId,
                sentAt: Int(Date().timeIntervalSince1970),
                flags: 0
            ).insert(dbConn)

            for labelId in activeLabels {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId).insert(dbConn)
            }
        }
    }

    private func threadLabels(_ db: AppDatabase, threadId: String = "t1") throws -> Set<String> {
        try db.read { dbConn in
            let rows = try ThreadLabelRecord
                .filter(Column("thread_id") == threadId)
                .fetchAll(dbConn)
            return Set(rows.map(\.labelId))
        }
    }

    private func threadLabelCount(_ db: AppDatabase, labelId: String, threadId: String = "t1") throws -> Int {
        try db.read { dbConn in
            try ThreadLabelRecord
                .filter(Column("thread_id") == threadId)
                .filter(Column("label_id") == labelId)
                .fetchCount(dbConn)
        }
    }

    private func threadHasUnread(_ db: AppDatabase, threadId: String = "t1") throws -> Int? {
        try db.read { dbConn in
            try ThreadRecord
                .filter(Column("id") == threadId)
                .fetchOne(dbConn)?
                .hasUnread
        }
    }

    private func messageFlags(_ db: AppDatabase, messageId: String = "m1") throws -> Int? {
        try db.read { dbConn in
            try MessageRecord
                .filter(Column("id") == messageId)
                .fetchOne(dbConn)?
                .flags
        }
    }

    private func expectMutationError(
        _ expected: MailMutationError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let error as MailMutationError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }

    // MARK: - Archive

    @Test func archiveRemovesINBOXLabel() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "STARRED"])

        let api = MockGmailAPI()
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        try await mutator.archive("t1", accountId: "acc1")

        let labels = try threadLabels(db)
        #expect(!labels.contains("INBOX"))
        #expect(labels.contains("STARRED"))

        #expect(api.modifyThreadCalls.count == 1)
        #expect(api.modifyThreadCalls[0].remove == ["INBOX"])
        #expect(api.modifyThreadCalls[0].add.isEmpty)
    }

    @Test func unarchiveAddsINBOXLabel() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["STARRED"])

        let api = MockGmailAPI()
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        try await mutator.unarchive("t1", accountId: "acc1")

        let labels = try threadLabels(db)
        #expect(labels.contains("INBOX"))
        #expect(api.modifyThreadCalls[0].add == ["INBOX"])
    }

    // MARK: - Star

    @Test func starAddsSTARREDLabel() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX"])

        let api = MockGmailAPI()
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        try await mutator.star("t1", accountId: "acc1")

        let labels = try threadLabels(db)
        #expect(labels.contains("STARRED"))
        #expect(api.modifyThreadCalls[0].add == ["STARRED"])
    }

    @Test func unstarRemovesSTARREDLabel() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "STARRED"])

        let api = MockGmailAPI()
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        try await mutator.unstar("t1", accountId: "acc1")

        let labels = try threadLabels(db)
        #expect(!labels.contains("STARRED"))
        #expect(labels.contains("INBOX"))
    }

    // MARK: - Trash

    @Test func trashAddsTRASHRemovesINBOX() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX"])

        let api = MockGmailAPI()
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        try await mutator.trash("t1", accountId: "acc1")

        let labels = try threadLabels(db)
        #expect(labels.contains("TRASH"))
        #expect(!labels.contains("INBOX"))
    }

    @Test func untrashRemovesTRASHAddsINBOX() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["TRASH"])

        let api = MockGmailAPI()
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        try await mutator.untrash("t1", accountId: "acc1")

        let labels = try threadLabels(db)
        #expect(labels.contains("INBOX"))
        #expect(!labels.contains("TRASH"))
    }

    // MARK: - Mark Read

    @Test func markReadUpdatesLocalFlags() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "UNREAD"])

        let api = MockGmailAPI()
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        try await mutator.markRead("t1", accountId: "acc1", read: true)

        let labels = try threadLabels(db)
        #expect(!labels.contains("UNREAD"))

        let thread = try db.read { dbConn in
            try ThreadRecord.filter(Column("id") == "t1").fetchOne(dbConn)
        }
        #expect(thread?.hasUnread == 0)

        let msg = try db.read { dbConn in
            try MessageRecord.filter(Column("id") == "m1").fetchOne(dbConn)
        }
        #expect(msg != nil)
        #expect((msg!.flags & MessageRecord.read) != 0)
    }

    @Test func markReadRollbackOnAPIFailureRestoresUnreadState() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "UNREAD"])

        let api = MockGmailAPI()
        api.modifyThreadResult = .failure(GmailAPIError.rateLimited(retryAfter: 12))
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        await expectMutationError(.rateLimited(retryAfter: 12)) {
            try await mutator.markRead("t1", accountId: "acc1", read: true)
        }

        let labels = try threadLabels(db)
        #expect(labels.contains("UNREAD"))
        #expect(try threadHasUnread(db) == 1)
        #expect(try messageFlags(db) == 0)
    }

    // MARK: - Rollback on API failure

    @Test func rollbacksOnAPIFailure() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "STARRED"])

        let api = MockGmailAPI()
        api.modifyThreadResult = .failure(GmailAPIError.serverError(statusCode: 500))
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        do {
            try await mutator.archive("t1", accountId: "acc1")
            Issue.record("Expected error")
        } catch {
            // Expected
        }

        // INBOX should be restored after rollback
        let labels = try threadLabels(db)
        #expect(labels.contains("INBOX"))
        #expect(labels.contains("STARRED"))
    }

    @Test func starRollbackOnAPIFailure() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX"])

        let api = MockGmailAPI()
        api.modifyThreadResult = .failure(GmailAPIError.serverError(statusCode: 500))
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        do {
            try await mutator.star("t1", accountId: "acc1")
            Issue.record("Expected error")
        } catch {
            // Expected
        }

        // STARRED should not be present after rollback
        let labels = try threadLabels(db)
        #expect(!labels.contains("STARRED"))
        #expect(labels.contains("INBOX"))
    }

    @Test func providerFactoryFailureDoesNotMutateLocalLabels() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "STARRED"])

        let mutator = MailMutator(db: db, apiFactory: { accountId in
            throw MailMutationError.missingCredential(accountId: accountId)
        })

        await expectMutationError(.missingCredential(accountId: "acc1")) {
            try await mutator.archive("t1", accountId: "acc1")
        }

        let labels = try threadLabels(db)
        #expect(labels == ["INBOX", "STARRED"])
    }

    @Test func repeatedArchiveIsIdempotent() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "STARRED"])

        let api = MockGmailAPI()
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        try await mutator.archive("t1", accountId: "acc1")
        try await mutator.archive("t1", accountId: "acc1")

        let labels = try threadLabels(db)
        #expect(!labels.contains("INBOX"))
        #expect(labels.contains("STARRED"))
        #expect(api.modifyThreadCalls.count == 2)
    }

    @Test func idempotentStarRollbackKeepsExistingStarredLabel() async throws {
        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "STARRED"])

        let api = MockGmailAPI()
        api.modifyThreadResult = .failure(GmailAPIError.serverError(statusCode: 500))
        let mutator = MailMutator(db: db, apiFactory: { _ in api })

        await expectMutationError(.degradedSync) {
            try await mutator.star("t1", accountId: "acc1")
        }

        let labels = try threadLabels(db)
        #expect(labels.contains("STARRED"))
        #expect(try threadLabelCount(db, labelId: "STARRED") == 1)
    }

    @Test func providerErrorsAreClassifiedForUserVisibleStates() {
        #expect(MailMutationError.provider(GmailAPIError.unauthorized) == .providerRejected(reason: .unauthorized))
        #expect(MailMutationError.provider(GmailAPIError.insufficientScope) == .providerRejected(reason: .insufficientScope))
        #expect(MailMutationError.provider(GmailAPIError.rateLimited(retryAfter: 5)) == .rateLimited(retryAfter: 5))
        #expect(MailMutationError.provider(GmailAPIError.serverError(statusCode: 503)) == .degradedSync)
        #expect(MailMutationError.provider(GmailAPIError.invalidResponse) == .degradedSync)
    }
}
