import Testing
import AuthKit
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
        activeLabels: [String] = ["INBOX", "STARRED"],
        hasUnread: Int = 1,
        messageFlags: Int = 0
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
                hasUnread: hasUnread
            ).insert(dbConn)

            try MessageRecord(
                id: "m1",
                threadId: threadId,
                accountId: accountId,
                sentAt: Int(Date().timeIntervalSince1970),
                flags: messageFlags
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

    private func hasUnread(_ db: AppDatabase, threadId: String = "t1") throws -> Int? {
        try db.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT has_unread FROM thread WHERE id = ?",
                arguments: [threadId]
            )
        }
    }

    private func messageFlags(_ db: AppDatabase, messageId: String = "m1") throws -> Int? {
        try db.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT flags FROM message WHERE id = ?",
                arguments: [messageId]
            )
        }
    }

    private enum MutationUnderTest: CaseIterable {
        case archive
        case star
        case markRead
        case trash

        var initialLabels: [String] {
            switch self {
            case .archive, .trash:
                return ["INBOX", "STARRED"]
            case .star:
                return ["INBOX", "STARRED"]
            case .markRead:
                return ["INBOX", "UNREAD"]
            }
        }

        var initialHasUnread: Int {
            self == .markRead ? 1 : 0
        }

        var initialMessageFlags: Int {
            self == .markRead ? 0 : MessageRecord.read
        }

        var repeatedInitialLabels: [String] {
            switch self {
            case .archive:
                return ["STARRED"]
            case .star:
                return ["INBOX", "STARRED"]
            case .markRead:
                return ["INBOX"]
            case .trash:
                return ["TRASH"]
            }
        }

        var repeatedHasUnread: Int {
            self == .markRead ? 0 : initialHasUnread
        }

        var repeatedMessageFlags: Int {
            self == .markRead ? MessageRecord.read : initialMessageFlags
        }
    }

    private func perform(
        _ operation: MutationUnderTest,
        using mutator: MailMutator,
        threadId: String = "t1",
        accountId: String = "acc1"
    ) async throws {
        switch operation {
        case .archive:
            try await mutator.archive(threadId, accountId: accountId)
        case .star:
            try await mutator.star(threadId, accountId: accountId)
        case .markRead:
            try await mutator.markRead(threadId, accountId: accountId, read: true)
        case .trash:
            try await mutator.trash(threadId, accountId: accountId)
        }
    }

    private func assertState(
        _ db: AppDatabase,
        labels: [String],
        hasUnread expectedUnread: Int,
        messageFlags expectedFlags: Int
    ) throws {
        #expect(try threadLabels(db) == Set(labels))
        #expect(try hasUnread(db) == expectedUnread)
        #expect(try messageFlags(db) == expectedFlags)
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

    @Test func factoryFailureDoesNotMutateLocalLabels() async throws {
        struct FactoryFailure: Error, Sendable {}

        let db = try await makeDB()
        try seedThreadWithLabels(db, activeLabels: ["INBOX", "STARRED"])

        let mutator = MailMutator(db: db, apiFactory: { _ in
            throw FactoryFailure()
        })

        do {
            try await mutator.archive("t1", accountId: "acc1")
            Issue.record("Expected factory error")
        } catch let error as MailMutationError {
            #expect(error.category == .providerUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let labels = try threadLabels(db)
        #expect(labels.contains("INBOX"))
        #expect(labels.contains("STARRED"))
    }

    @Test func providerFailureRollsBackArchiveStarReadAndTrash() async throws {
        for operation in MutationUnderTest.allCases {
            let db = try await makeDB()
            try seedThreadWithLabels(
                db,
                activeLabels: operation.initialLabels,
                hasUnread: operation.initialHasUnread,
                messageFlags: operation.initialMessageFlags
            )

            let api = MockGmailAPI()
            api.modifyThreadResult = .failure(GmailAPIError.serverError(statusCode: 500))
            let mutator = MailMutator(db: db, apiFactory: { _ in api })

            do {
                try await perform(operation, using: mutator)
                Issue.record("Expected provider failure for \(operation)")
            } catch let error as MailMutationError {
                #expect(error.category == .providerUnavailable)
            } catch {
                Issue.record("Expected MailMutationError, got \(error)")
            }

            try assertState(
                db,
                labels: operation.initialLabels,
                hasUnread: operation.initialHasUnread,
                messageFlags: operation.initialMessageFlags
            )
        }
    }

    @Test func missingCredentialDoesNotOptimisticallyMutateArchiveStarReadAndTrash() async throws {
        for operation in MutationUnderTest.allCases {
            let db = try await makeDB()
            try seedThreadWithLabels(
                db,
                activeLabels: operation.initialLabels,
                hasUnread: operation.initialHasUnread,
                messageFlags: operation.initialMessageFlags
            )

            let mutator = MailMutator(db: db, apiFactory: { accountId in
                throw AuthError.missingCredential(accountID: accountId)
            })

            do {
                try await perform(operation, using: mutator)
                Issue.record("Expected missing credential for \(operation)")
            } catch let error as MailMutationError {
                #expect(error.category == .missingCredential)
            } catch {
                Issue.record("Expected MailMutationError, got \(error)")
            }

            try assertState(
                db,
                labels: operation.initialLabels,
                hasUnread: operation.initialHasUnread,
                messageFlags: operation.initialMessageFlags
            )
        }
    }

    @Test func rateLimitRollsBackArchiveStarReadAndTrash() async throws {
        for operation in MutationUnderTest.allCases {
            let db = try await makeDB()
            try seedThreadWithLabels(
                db,
                activeLabels: operation.initialLabels,
                hasUnread: operation.initialHasUnread,
                messageFlags: operation.initialMessageFlags
            )

            let api = MockGmailAPI()
            api.modifyThreadResult = .failure(GmailAPIError.rateLimited(retryAfter: 30))
            let mutator = MailMutator(db: db, apiFactory: { _ in api })

            do {
                try await perform(operation, using: mutator)
                Issue.record("Expected rate limit for \(operation)")
            } catch let error as MailMutationError {
                #expect(error.category == .rateLimited)
            } catch {
                Issue.record("Expected MailMutationError, got \(error)")
            }

            try assertState(
                db,
                labels: operation.initialLabels,
                hasUnread: operation.initialHasUnread,
                messageFlags: operation.initialMessageFlags
            )
        }
    }

    @Test func repeatedOperationsKeepLocalStateStable() async throws {
        for operation in MutationUnderTest.allCases {
            let db = try await makeDB()
            try seedThreadWithLabels(
                db,
                activeLabels: operation.repeatedInitialLabels,
                hasUnread: operation.repeatedHasUnread,
                messageFlags: operation.repeatedMessageFlags
            )

            let api = MockGmailAPI()
            let mutator = MailMutator(db: db, apiFactory: { _ in api })

            try await perform(operation, using: mutator)

            try assertState(
                db,
                labels: operation.repeatedInitialLabels,
                hasUnread: operation.repeatedHasUnread,
                messageFlags: operation.repeatedMessageFlags
            )
        }
    }

    @Test func mutationErrorsExposeDistinctUserVisibleMessages() {
        let samples: [(MailProviderErrorCategory, String)] = [
            (.missingCredential, "Reconnect Gmail"),
            (.insufficientScope, "re-authorization"),
            (.rateLimited, "rate-limited"),
            (.offline, "offline"),
            (.providerUnavailable, "rejected")
        ]

        for (category, fragment) in samples {
            let error = MailMutationError(operation: .archive, category: category)
            #expect(error.localizedDescription.contains(fragment))
        }
    }
}
