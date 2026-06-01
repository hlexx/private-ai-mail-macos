import Foundation
import GRDB
import IntegrationDomain
import MailDomain
import MailProviders
import Persistence
import Testing
@testable import MailSync

@Suite("GmailActionExecutor")
struct GmailActionExecutorTests {
    @Test func createsProviderDraftFromSanitizedActionPayload() async throws {
        let db = try AppDatabase.openInMemorySync()
        let api = MockGmailAPI()
        api.createDraftResult = .success(
            GmailDTO.Draft(
                id: "draft-1",
                message: GmailDTO.Message(id: "message-1", threadId: "thread-1", labelIds: ["DRAFT"])
            )
        )
        let executor = GmailActionExecutor(db: db, apiFactory: { _ in api }, now: fixedNow)

        let result = await executor.execute(command: try draftCommand())

        #expect(result.status == .succeeded)
        #expect(result.externalResultId == "gmail:draft:draft-1")
        #expect(api.createDraftCalls.count == 1)
        #expect(api.createDraftCalls[0].threadId == "thread-1")
        let metadata = try metadataString(result.metadata)
        #expect(metadata.contains("Draft body") == false)
        #expect(metadata.contains("recipient@example.com") == false)
    }

    @Test func archivesThreadThroughMailMutatorAndReturnsPrivacySafeResult() async throws {
        let db = try AppDatabase.openInMemorySync()
        try seedThread(db, labels: ["INBOX", "STARRED"])
        let api = MockGmailAPI()
        let executor = GmailActionExecutor(db: db, apiFactory: { _ in api }, now: fixedNow)

        let result = await executor.execute(command: try actionCommand(kind: .archiveThread))

        #expect(result.status == .succeeded)
        #expect(result.externalResultId == "gmail:thread:thread-1")
        #expect(api.modifyThreadCalls.map(\.remove) == [["INBOX"]])
        #expect(try labels(db) == ["STARRED"])
    }

    @Test func completedOutboxExecutionSuppressesDuplicateProviderWrite() async throws {
        let db = try AppDatabase.openInMemorySync()
        try seedThread(db, labels: ["INBOX"])
        try insertOutboxRecord(db, opId: "op-duplicate", kind: .archiveThread)
        let api = MockGmailAPI()
        let executor = GmailActionExecutor(db: db, apiFactory: { _ in api }, now: fixedNow)
        let store = ActionOutboxExecutionStore(
            db: db,
            executor: executor,
            now: fixedNow,
            makeEventId: { "event-\(UUID().uuidString)" }
        )

        let first = try await store.execute(opId: "op-duplicate")
        let second = try await store.execute(opId: "op-duplicate")

        #expect(first.status == .succeeded)
        #expect(second.status == .succeeded)
        #expect(api.modifyThreadCalls.count == 1)
        let attemptCount = try db.read { database in
            try ActionAttemptRecord.fetchCount(database)
        }
        #expect(attemptCount == 1)
    }

    @Test func expiredAuthMapsToAuthenticationRequiredWithoutRawProviderDetails() async throws {
        let result = try await actionFailureResult(error: GmailAPIError.unauthorized)

        #expect(result.status == .failed)
        #expect(result.failureKind == .authenticationRequired)
        #expect(try metadataString(result.metadata).contains("401") == false)
    }

    @Test func retryableProviderFailureMapsToRateLimited() async throws {
        let result = try await actionFailureResult(error: GmailAPIError.rateLimited(retryAfter: 30))

        #expect(result.status == .failed)
        #expect(result.failureKind == .rateLimited)
    }

    @Test func nonRetryableProviderFailureMapsToPermissionDenied() async throws {
        let result = try await actionFailureResult(error: GmailAPIError.insufficientScope)

        #expect(result.status == .failed)
        #expect(result.failureKind == .permissionDenied)
    }

    @Test func outboxFailurePersistsRetryabilityFromProviderFailure() async throws {
        let db = try AppDatabase.openInMemorySync()
        try seedThread(db, labels: ["INBOX"])
        try insertOutboxRecord(db, opId: "op-rate-limited", kind: .archiveThread)
        let api = MockGmailAPI()
        api.modifyThreadResult = .failure(GmailAPIError.rateLimited(retryAfter: 30))
        let executor = GmailActionExecutor(db: db, apiFactory: { _ in api }, now: fixedNow)
        let store = ActionOutboxExecutionStore(db: db, executor: executor, now: fixedNow)

        let result = try await store.execute(opId: "op-rate-limited")

        #expect(result.status == .failed)
        let attempt = try db.read { database in
            try ActionAttemptRecord.fetchOne(
                database,
                key: ["op_id": "op-rate-limited", "attempt_number": 1]
            )
        }
        #expect(attempt?.retryable == 1)
        #expect(attempt?.errorCode == ActionFailureKind.rateLimited.rawValue)
    }

    private func actionFailureResult(error: Error) async throws -> ActionResult {
        let db = try AppDatabase.openInMemorySync()
        try seedThread(db, labels: ["INBOX"])
        let api = MockGmailAPI()
        api.modifyThreadResult = .failure(error)
        let executor = GmailActionExecutor(db: db, apiFactory: { _ in api }, now: fixedNow)
        return await executor.execute(command: try actionCommand(kind: .archiveThread))
    }

    private func actionCommand(kind: ActionKind) throws -> ActionCommand {
        let requirement = ActionPolicy.defaultApprovalRequirement(for: kind)
        return try ActionCommand(
            opId: "op-\(kind.rawValue)",
            accountId: "account-1",
            target: .thread(accountId: "account-1", threadId: "thread-1"),
            kind: kind,
            idempotencyKey: ActionIdempotencyKey(rawValue: "idem-\(kind.rawValue)"),
            approvalRequirement: requirement,
            approvalState: .approved
        )
    }

    private func draftCommand() throws -> ActionCommand {
        let requirement = ActionPolicy.defaultApprovalRequirement(for: .draftReply)
        return try ActionCommand(
            opId: "op-draft",
            accountId: "account-1",
            target: .thread(accountId: "account-1", threadId: "thread-1"),
            kind: .draftReply,
            payload: ActionPayload(encoding: draftPayload()),
            idempotencyKey: ActionIdempotencyKey(rawValue: "idem-draft"),
            approvalRequirement: requirement,
            approvalState: .approved
        )
    }

    private func draftPayload() -> GmailDraftActionPayload {
        GmailDraftActionPayload(
            accountID: "account-1",
            from: Address(email: "me@example.com"),
            to: [Address(email: "recipient@example.com")],
            subject: "Draft subject",
            bodyText: "Draft body",
            rfcInReplyTo: "<parent@example.com>"
        )
    }

    private func insertOutboxRecord(
        _ db: AppDatabase,
        opId: String,
        kind: ActionKind
    ) throws {
        let requirement = ActionPolicy.defaultApprovalRequirement(for: kind)
        let record = ActionOutboxRecord(
            opId: opId,
            accountId: "account-1",
            targetKind: ActionTargetKind.thread.rawValue,
            threadId: "thread-1",
            actionKind: kind.rawValue,
            actionSchemaVersion: ActionPayload.currentSchemaVersion,
            idempotencyKey: "idem-\(opId)",
            approvalRequirement: requirement.rawValue,
            approvalState: ApprovalState.approved.rawValue,
            status: ActionStatus.ready.rawValue,
            payloadJSON: try payloadJSON(ActionPayload()),
            createdAt: 100,
            updatedAt: 100,
            approvedAt: 100
        )
        try db.dbQueue.write { database in
            try record.insert(database)
        }
    }

    private func seedThread(
        _ db: AppDatabase,
        labels activeLabels: [String]
    ) throws {
        try db.dbQueue.write { database in
            try AccountRecord(id: "account-1", email: "me@example.com", createdAt: 100).insert(database)
            for label in ["INBOX", "STARRED", "TRASH", "UNREAD"] {
                try LabelRecord(id: label, accountId: "account-1", name: label, type: .system).insert(database)
            }
            try ThreadRecord(
                id: "thread-1",
                accountId: "account-1",
                subject: "Thread",
                lastMessageAt: 100,
                messageCount: 1
            ).insert(database)
            try MessageRecord(id: "message-1", threadId: "thread-1", accountId: "account-1", sentAt: 100)
                .insert(database)
            for label in activeLabels {
                try ThreadLabelRecord(accountId: "account-1", threadId: "thread-1", labelId: label)
                    .insert(database)
            }
        }
    }

    private func labels(_ db: AppDatabase) throws -> Set<String> {
        try db.dbQueue.read { database in
            let records = try ThreadLabelRecord
                .filter(Column("account_id") == "account-1" && Column("thread_id") == "thread-1")
                .fetchAll(database)
            return Set(records.map(\.labelId))
        }
    }

    private func payloadJSON(_ payload: ActionPayload) throws -> String {
        let data = try JSONEncoder().encode(payload)
        return try #require(String(data: data, encoding: .utf8))
    }

    private func metadataString(_ metadata: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(metadata)
        return try #require(String(data: data, encoding: .utf8))
    }

    private func fixedNow() -> Date {
        Date(timeIntervalSince1970: 200)
    }
}
