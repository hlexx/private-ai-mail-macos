import ActionsFeature
import Foundation
import GRDB
import IntegrationDomain
import MailDomain
import MailSync
import Persistence
import Testing
@testable import PrivateAIMail

@Suite("ActionQueueService")
struct ActionQueueServiceTests {
    @MainActor
    @Test func draftReplyBuildsProviderDraftPayloadAndExecutesOutbox() async throws {
        let db = try AppDatabase.openInMemorySync()
        try seedDraftThread(db)
        let executor = RecordingActionExecutor()
        let service = ActionQueueService(
            db: db,
            executionStore: ActionOutboxExecutionStore(db: db, executor: executor, now: fixedNow),
            now: fixedNow
        )

        let outcome = await service.start(TrustActionRequest(
            requestId: "draft-op-1",
            action: .draftReply,
            target: TrustActionTarget(accountId: "account-1", threadId: "thread-1", subject: "Contract")
        ))

        #expect(outcome.status == .completed)
        let command = try #require(await executor.firstCommand())
        #expect(command.kind == .draftReply)
        #expect(command.status == .executing)

        let data = try JSONEncoder().encode(command.payload.body)
        let payload = try JSONDecoder().decode(GmailDraftActionPayload.self, from: data)
        #expect(payload.accountID == "account-1")
        #expect(payload.from.email == "me@example.com")
        #expect(payload.to == [Address(name: "Client", email: "client@example.com")])
        #expect(payload.subject == "Re: Contract")
        #expect(payload.threadID == "thread-1")
        #expect(payload.rfcInReplyTo == "<client-message@example.com>")
        #expect(payload.rfcReferences == ["<client-message@example.com>"])

        let outbox = try db.read { database in
            try ActionOutboxRecord.fetchOne(database, key: "draft-op-1")
        }
        #expect(outbox?.status == ActionStatus.succeeded.rawValue)
        #expect(outbox?.externalResultId == "provider:draft:draft-op-1")
    }
}

private actor RecordingActionExecutor: ActionExecuting {
    private var commands: [ActionCommand] = []

    func execute(command: ActionCommand) async -> ActionResult {
        commands.append(command)
        return ActionResult(
            status: .succeeded,
            externalResultId: "provider:draft:\(command.opId)",
            completedAt: fixedNow(),
            metadata: .object([
                "actionKind": .string(command.kind.rawValue),
                "executor": .string("test"),
                "result": .string("accepted"),
                "targetKind": .string(command.target.kind.rawValue),
            ])
        )
    }

    func firstCommand() -> ActionCommand? {
        commands.first
    }
}

private func seedDraftThread(_ db: AppDatabase) throws {
    try db.dbQueue.write { database in
        try AccountRecord(
            id: "account-1",
            email: "me@example.com",
            displayName: "Me",
            createdAt: 100
        ).insert(database)
        try ThreadRecord(
            id: "thread-1",
            accountId: "account-1",
            subject: "Contract",
            lastMessageAt: 100,
            messageCount: 1
        ).insert(database)
        try MessageRecord(
            id: "message-1",
            threadId: "thread-1",
            accountId: "account-1",
            messageIdHeader: "<client-message@example.com>",
            fromAddr: "Client <client@example.com>",
            toAddr: "Me <me@example.com>",
            sentAt: 100,
            bodyText: "Please send the contract draft."
        ).insert(database)
    }
}

private func fixedNow() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}
