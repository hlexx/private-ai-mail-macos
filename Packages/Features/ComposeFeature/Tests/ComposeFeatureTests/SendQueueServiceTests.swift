import Foundation
import GRDB
import MailDomain
import Persistence
import Testing
@testable import ComposeFeature

@Suite("SendQueueService", .serialized)
struct SendQueueServiceTests {
    @Test func offlinePreflightSchedulesRetryWithoutProviderSendOrLocalSentState() async throws {
        let db = try await makeDatabase()
        let clock = TestClock(Date(timeIntervalSince1970: 2_000))
        let provider = MockMailSendProvider()
        let credentials = MockSendQueueCredentialAuthorizer(
            authorization: SendQueueCredentialAuthorization(
                status: .offline,
                providerErrorCode: "network_offline"
            )
        )
        let service = SendQueueService(
            db: db,
            providers: [provider],
            credentialAuthorizer: credentials,
            now: { clock.now() }
        )

        let queued = try await service.enqueueDraft(makeDraft(), id: "queue-offline", idempotencyKey: "idem-offline")
        let outcome = try await service.executeNextEligible()

        guard case .retryScheduled(let updated) = outcome else {
            Issue.record("Expected retryScheduled, got \(outcome)")
            return
        }
        #expect(updated.id == queued.id)
        #expect(updated.status == .retryScheduled)
        #expect(updated.sanitizedFailure?.category == .offline)
        #expect(updated.nextAttemptAt == Date(timeIntervalSince1970: 2_060))
        #expect(updated.attempts == 0)
        #expect(provider.requests.isEmpty)
        #expect(try messageCount(db: db) == 0)
    }

    @Test func missingCredentialAndScopePreflightMoveToNeedsConsentWithoutProviderSend() async throws {
        for status in [SendQueueCredentialStatus.missingCredential, .insufficientScope] {
            let db = try await makeDatabase()
            let provider = MockMailSendProvider()
            let credentials = MockSendQueueCredentialAuthorizer(
                authorization: SendQueueCredentialAuthorization(status: status)
            )
            let service = SendQueueService(
                db: db,
                providers: [provider],
                credentialAuthorizer: credentials,
                now: { Date(timeIntervalSince1970: 2_100) }
            )

            _ = try await service.enqueueDraft(
                makeDraft(id: DraftID(rawValue: "draft-\(status)"), subject: "Scope \(status)"),
                id: SendQueueItemID(rawValue: "queue-\(status)"),
                idempotencyKey: SendIdempotencyKey(rawValue: "idem-\(status)")
            )
            let outcome = try await service.executeNextEligible()

            guard case .needsConsent(let updated) = outcome else {
                Issue.record("Expected needsConsent for \(status), got \(outcome)")
                return
            }
            #expect(updated.status == .needsConsent)
            #expect(updated.sanitizedFailure?.category == status.expectedFailureCategory)
            #expect(updated.attempts == 0)
            #expect(provider.requests.isEmpty)
            #expect(try messageCount(db: db) == 0)
        }
    }

    @Test func providerValidationFailureMarksFailedAndDoesNotInsertLocalSentState() async throws {
        let db = try await makeDatabase()
        let failure = SanitizedSendFailure(
            category: .validation,
            providerErrorCode: "missing_recipients",
            occurredAt: Date(timeIntervalSince1970: 2_200)
        )
        let provider = MockMailSendProvider(results: [.failure(ProviderSendError(failure: failure))])
        let service = SendQueueService(
            db: db,
            providers: [provider],
            now: { Date(timeIntervalSince1970: 2_200) }
        )

        _ = try await service.enqueueDraft(makeDraft(), id: "queue-failed", idempotencyKey: "idem-failed")
        let outcome = try await service.executeNextEligible()

        guard case .failed(let updated) = outcome else {
            Issue.record("Expected failed, got \(outcome)")
            return
        }
        #expect(updated.status == .failed)
        #expect(updated.attempts == 1)
        #expect(updated.sanitizedFailure?.category == .validation)
        #expect(provider.requests.count == 1)
        #expect(try messageCount(db: db) == 0)
    }

    @Test func rateLimitFailureSchedulesRetryFromProviderRetryAfter() async throws {
        let db = try await makeDatabase()
        let failure = SanitizedSendFailure(
            category: .rateLimited,
            providerErrorCode: "429",
            retryAfterSeconds: 120,
            occurredAt: Date(timeIntervalSince1970: 2_300)
        )
        let provider = MockMailSendProvider(results: [.failure(ProviderSendError(failure: failure))])
        let service = SendQueueService(
            db: db,
            providers: [provider],
            now: { Date(timeIntervalSince1970: 2_300) }
        )

        _ = try await service.enqueueDraft(makeDraft(), id: "queue-rate-limit", idempotencyKey: "idem-rate-limit")
        let outcome = try await service.executeNextEligible()

        guard case .retryScheduled(let updated) = outcome else {
            Issue.record("Expected retryScheduled, got \(outcome)")
            return
        }
        #expect(updated.status == .retryScheduled)
        #expect(updated.attempts == 1)
        #expect(updated.nextAttemptAt == Date(timeIntervalSince1970: 2_420))
        #expect(updated.sanitizedFailure?.category == .rateLimited)
        #expect(provider.requests.count == 1)
    }

    @Test func duplicateEnqueueReturnsExistingQueueItemAndDoesNotSendTwice() async throws {
        let db = try await makeDatabase()
        let provider = MockMailSendProvider()
        let service = SendQueueService(
            db: db,
            providers: [provider],
            now: { Date(timeIntervalSince1970: 2_400) }
        )
        let draft = makeDraft(id: "draft-dup")

        let first = try await service.enqueueDraft(draft, id: "queue-dup-1", idempotencyKey: "idem-dup")
        let second = try await service.enqueueDraft(draft, id: "queue-dup-2", idempotencyKey: "idem-dup")
        let firstOutcome = try await service.executeNextEligible()
        let secondOutcome = try await service.executeNextEligible()

        #expect(second.id == first.id)
        guard case .sent = firstOutcome else {
            Issue.record("Expected sent, got \(firstOutcome)")
            return
        }
        #expect(secondOutcome == .noEligibleItem)
        #expect(provider.requests.count == 1)
        #expect(try sendQueueCount(db: db) == 1)
    }

    @Test func duplicateProviderSuccessDoesNotDuplicateLocalRowsOrThreadCount() async throws {
        let db = try await makeDatabase()
        try await seedThread(db: db, id: "thread-existing", messageCount: 2)
        let provider = MockMailSendProvider(
            results: [
                .success(ProviderSendResult(
                    provider: .gmail,
                    providerMessageID: "provider-duplicate",
                    providerThreadID: "thread-existing",
                    rfcMessageID: "<duplicate@example.com>",
                    sentAt: Date(timeIntervalSince1970: 2_500)
                )),
                .success(ProviderSendResult(
                    provider: .gmail,
                    providerMessageID: "provider-duplicate",
                    providerThreadID: "thread-existing",
                    rfcMessageID: "<duplicate@example.com>",
                    sentAt: Date(timeIntervalSince1970: 2_501)
                )),
            ]
        )
        let service = SendQueueService(
            db: db,
            providers: [provider],
            now: { Date(timeIntervalSince1970: 2_500) }
        )
        let reply = makeDraft(
            id: "draft-reply-1",
            subject: "Re: Existing",
            threadID: "thread-existing",
            replyToProviderMessageID: "provider-original"
        )
        let duplicateReply = makeDraft(
            id: "draft-reply-2",
            subject: "Re: Existing",
            threadID: "thread-existing",
            replyToProviderMessageID: "provider-original"
        )

        _ = try await service.enqueueDraft(reply, id: "queue-reply-1", idempotencyKey: "idem-reply-1")
        _ = try await service.enqueueDraft(duplicateReply, id: "queue-reply-2", idempotencyKey: "idem-reply-2")
        _ = try await service.executeNextEligible()
        _ = try await service.executeNextEligible()

        let state = try localSentState(db: db, messageID: "provider-duplicate", threadID: "thread-existing")
        #expect(state.messages == 1)
        #expect(state.labels == 1)
        #expect(state.threadMessageCount == 3)
        #expect(provider.requests.count == 2)
    }

    @Test func cancellationSkipsProviderExecution() async throws {
        let db = try await makeDatabase()
        let provider = MockMailSendProvider()
        let service = SendQueueService(
            db: db,
            providers: [provider],
            now: { Date(timeIntervalSince1970: 2_600) }
        )

        let queued = try await service.enqueueDraft(makeDraft(), id: "queue-cancel", idempotencyKey: "idem-cancel")
        let canceled = try await service.cancel(id: queued.id)
        let outcome = try await service.executeNextEligible()

        #expect(canceled?.status == .canceled)
        #expect(outcome == .noEligibleItem)
        #expect(provider.requests.isEmpty)
        #expect(try messageCount(db: db) == 0)
    }

    @Test func newServiceInstanceFetchesPersistedPendingItemAfterRestart() async throws {
        let db = try await makeDatabase()
        let provider = MockMailSendProvider()
        let firstService = SendQueueService(
            db: db,
            providers: [provider],
            now: { Date(timeIntervalSince1970: 2_700) }
        )
        _ = try await firstService.enqueueDraft(makeDraft(), id: "queue-restart", idempotencyKey: "idem-restart")

        let restartedService = SendQueueService(
            db: db,
            providers: [provider],
            now: { Date(timeIntervalSince1970: 2_701) }
        )
        let outcome = try await restartedService.executeNextEligible()

        guard case .sent(let updated) = outcome else {
            Issue.record("Expected sent after restart fetch, got \(outcome)")
            return
        }
        #expect(updated.id == "queue-restart")
        #expect(updated.status == .sent)
        #expect(provider.requests.count == 1)
        #expect(try messageCount(db: db) == 1)
    }

    private func makeDatabase() async throws -> AppDatabase {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        try await DatabaseActor.shared.run {
            try db.write { database in
                try AccountRecord(
                    id: "account-1",
                    provider: "gmail",
                    email: "me@example.com",
                    createdAt: 1_000
                ).insert(database)
            }
        }
        return db
    }

    private func seedThread(db: AppDatabase, id: String, messageCount: Int) async throws {
        try await DatabaseActor.shared.run {
            try db.write { database in
                try ThreadRecord(
                    id: id,
                    accountId: "account-1",
                    subject: "Existing",
                    snippet: "Earlier",
                    lastMessageAt: 1_000,
                    messageCount: messageCount
                ).insert(database)
            }
        }
    }

    private func makeDraft(
        id: DraftID = "draft-1",
        subject: String = "Queued subject",
        threadID: String? = nil,
        replyToProviderMessageID: String? = nil
    ) -> DraftMessage {
        DraftMessage(
            id: id,
            provider: .gmail,
            accountID: "account-1",
            from: Address(name: "Me", email: "me@example.com"),
            to: [Address(name: "Recipient", email: "recipient@example.com")],
            subject: subject,
            bodyText: "Queued body stays local",
            threadID: threadID,
            replyToProviderMessageID: replyToProviderMessageID,
            rfcMessageID: "<\(id.rawValue)@hlexx.privateaimail>",
            rfcInReplyTo: replyToProviderMessageID.map { "<\($0)@example.com>" },
            rfcReferences: replyToProviderMessageID.map { ["<\($0)@example.com>"] } ?? [],
            createdAt: Date(timeIntervalSince1970: 1_500),
            updatedAt: Date(timeIntervalSince1970: 1_501)
        )
    }

    private func messageCount(db: AppDatabase) throws -> Int {
        try db.read { database in
            try MessageRecord.fetchCount(database)
        }
    }

    private func sendQueueCount(db: AppDatabase) throws -> Int {
        try db.read { database in
            try SendQueueItemRecord.fetchCount(database)
        }
    }

    private func localSentState(
        db: AppDatabase,
        messageID: String,
        threadID: String
    ) throws -> (messages: Int, labels: Int, threadMessageCount: Int?) {
        try db.read { database in
            let messages = try MessageRecord
                .filter(Column("account_id") == "account-1" && Column("id") == messageID)
                .fetchCount(database)
            let labels = try ThreadLabelRecord
                .filter(Column("account_id") == "account-1" && Column("thread_id") == threadID && Column("label_id") == "SENT")
                .fetchCount(database)
            let thread = try ThreadRecord.fetchOne(database, key: ["account_id": "account-1", "id": threadID])
            return (messages, labels, thread?.messageCount)
        }
    }
}

private final class TestClock: @unchecked Sendable {
    private let current: Date

    init(_ current: Date) {
        self.current = current
    }

    func now() -> Date {
        current
    }
}

private final class MockSendQueueCredentialAuthorizer: SendQueueCredentialAuthorizing, @unchecked Sendable {
    var authorization: SendQueueCredentialAuthorization
    private(set) var checkedItems: [SendQueueItemID] = []

    init(authorization: SendQueueCredentialAuthorization) {
        self.authorization = authorization
    }

    func authorization(for item: QueuedOutgoingMessage) async -> SendQueueCredentialAuthorization {
        checkedItems.append(item.id)
        return authorization
    }
}

private final class MockMailSendProvider: MailSendProvider, @unchecked Sendable {
    let provider: MailProviderIdentifier
    var results: [Result<ProviderSendResult, Error>]
    private(set) var requests: [ProviderSendRequest] = []

    init(
        provider: MailProviderIdentifier = .gmail,
        results: [Result<ProviderSendResult, Error>] = []
    ) {
        self.provider = provider
        self.results = results
    }

    func send(_ request: ProviderSendRequest) async throws -> ProviderSendResult {
        requests.append(request)
        if !results.isEmpty {
            return try results.removeFirst().get()
        }
        return ProviderSendResult(
            provider: provider,
            providerMessageID: "provider-\(request.idempotencyKey.rawValue)",
            providerThreadID: request.threadID ?? "thread-\(request.idempotencyKey.rawValue)",
            rfcMessageID: request.rfcMessageID,
            sentAt: Date(timeIntervalSince1970: 3_000)
        )
    }
}

private extension SendQueueCredentialStatus {
    var expectedFailureCategory: SendFailureCategory {
        switch self {
        case .authorized:
            return .unknown
        case .offline:
            return .offline
        case .missingCredential:
            return .missingCredential
        case .insufficientScope:
            return .insufficientScope
        case .authExpired:
            return .authExpired
        }
    }
}
