import AttachmentKit
import Foundation
import GRDB
import Persistence
import Testing
@testable import AttachmentRAG

@Suite("Local attachment processing queue")
struct LocalAttachmentProcessingQueueTests {
    @Test func missingLocalBytesWritesWaitingJobWithoutExtraction() async throws {
        let database = try makeDatabase()
        try seedAttachmentGraph(database, attachments: [
            attachment(id: "att1", filename: "invoice.pdf", mime: "application/pdf"),
        ])
        let byteStore = try makeByteStore()
        let events = AttachmentProcessingEventRecorder()
        let queue = LocalAttachmentProcessingQueue(
            database: database,
            byteStore: byteStore.store,
            eventSink: { events.record($0) }
        )

        try await queue.enqueueMessage(accountId: "a1", messageId: "m1")

        try await waitUntil("missing bytes job") {
            try job(database, attachmentId: "att1")?.status == "waiting_for_local_file"
        }

        #expect(try extractionCount(database, attachmentId: "att1") == 0)
        #expect(events.contains(kind: .skippedMissingBytes, attachmentId: "att1"))
    }

    @Test func successfulTextExtractionWritesExtractionChunksArtifactAndSucceededJob() async throws {
        let database = try makeDatabase()
        try seedAttachmentGraph(database, attachments: [
            attachment(id: "att1", filename: "invoice.txt", mime: "text/plain"),
        ])
        let byteStore = try makeByteStore()
        let data = Data("Invoice: INV-42\nTotal: 42.00\nPayment due Friday".utf8)
        try byteStore.store.store(data, for: key(attachmentId: "att1"))
        let queue = LocalAttachmentProcessingQueue(database: database, byteStore: byteStore.store)

        try await queue.enqueueMessage(accountId: "a1", messageId: "m1")

        try await waitUntil("successful processing") {
            try job(database, attachmentId: "att1")?.status == "succeeded"
        }

        let extraction = try extraction(database, attachmentId: "att1")
        #expect(extraction?.status == "complete")
        #expect(extraction?.contentHash?.hasPrefix("sha256:") == true)
        #expect(extraction?.byteCount == data.count)
        #expect(try chunkCount(database, attachmentId: "att1") > 0)
        #expect(try artifactCount(database, attachmentId: "att1") == 1)
    }

    @Test func unsupportedFormatWritesUnsupportedExtractionAndJob() async throws {
        let database = try makeDatabase()
        try seedAttachmentGraph(database, attachments: [
            attachment(
                id: "att1",
                filename: "proposal.docx",
                mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            ),
        ])
        let byteStore = try makeByteStore()
        try byteStore.store.store(Data("not a real docx".utf8), for: key(attachmentId: "att1"))
        let queue = LocalAttachmentProcessingQueue(database: database, byteStore: byteStore.store)

        try await queue.enqueueMessage(accountId: "a1", messageId: "m1")

        try await waitUntil("unsupported processing") {
            try job(database, attachmentId: "att1")?.status == "unsupported"
        }

        let extraction = try extraction(database, attachmentId: "att1")
        #expect(extraction?.status == "unsupported")
        #expect(extraction?.errorCode == "unsupportedDocumentFormat")
        #expect(try artifactCount(database, attachmentId: "att1") == 0)
    }

    @Test func extractionFailureWritesFailedExtractionAndJob() async throws {
        let database = try makeDatabase()
        try seedAttachmentGraph(database, attachments: [
            attachment(id: "att1", filename: "broken.pdf", mime: "application/pdf"),
        ])
        let byteStore = try makeByteStore()
        try byteStore.store.store(Data(), for: key(attachmentId: "att1"))
        let queue = LocalAttachmentProcessingQueue(database: database, byteStore: byteStore.store)

        try await queue.enqueueMessage(accountId: "a1", messageId: "m1")

        try await waitUntil("failed processing") {
            try job(database, attachmentId: "att1")?.status == "failed"
        }

        let extraction = try extraction(database, attachmentId: "att1")
        #expect(extraction?.status == "failed")
        #expect(extraction?.errorCode == "unreadablePDF")
        #expect(try job(database, attachmentId: "att1")?.lastErrorCode == "unreadablePDF")
    }

    @Test func cancellationMarksRunningJobCancelled() async throws {
        let database = try makeDatabase()
        try seedAttachmentGraph(database, attachments: [
            attachment(id: "att1", filename: "invoice.txt", mime: "text/plain"),
        ])
        let byteStore = try makeByteStore()
        try byteStore.store.store(Data("Invoice total due Friday".utf8), for: key(attachmentId: "att1"))
        let extractor = BlockingAttachmentExtractor(result: completeExtractionResult)
        let events = AttachmentProcessingEventRecorder()
        let queue = LocalAttachmentProcessingQueue(
            database: database,
            byteStore: byteStore.store,
            extractor: extractor,
            configuration: LocalAttachmentProcessingQueueConfiguration(maxConcurrentTasks: 1),
            eventSink: { events.record($0) }
        )

        try await queue.enqueueMessage(accountId: "a1", messageId: "m1")
        #expect(extractor.waitForEntries(1))

        await queue.cancelAll()
        extractor.release(1)

        try await waitUntil("cancelled job") {
            try job(database, attachmentId: "att1")?.status == "cancelled"
        }
        try await waitUntil("cancelled event") {
            events.contains(kind: .cancelled, attachmentId: "att1")
        }
        #expect(events.contains(kind: .cancelled, attachmentId: "att1"))
    }

    @Test func concurrencyLimitBoundsRunningExtractionTasks() async throws {
        let database = try makeDatabase()
        try seedAttachmentGraph(database, attachments: [
            attachment(id: "att1", filename: "one.txt", mime: "text/plain"),
            attachment(id: "att2", filename: "two.txt", mime: "text/plain"),
            attachment(id: "att3", filename: "three.txt", mime: "text/plain"),
        ])
        let byteStore = try makeByteStore()
        for attachmentId in ["att1", "att2", "att3"] {
            try byteStore.store.store(
                Data("Invoice \(attachmentId) total due Friday".utf8),
                for: key(attachmentId: attachmentId)
            )
        }
        let extractor = BlockingAttachmentExtractor(result: completeExtractionResult)
        let queue = LocalAttachmentProcessingQueue(
            database: database,
            byteStore: byteStore.store,
            extractor: extractor,
            configuration: LocalAttachmentProcessingQueueConfiguration(maxConcurrentTasks: 2)
        )

        try await queue.enqueueMessage(accountId: "a1", messageId: "m1")
        #expect(extractor.waitForEntries(2))
        try await Task.sleep(nanoseconds: 100_000_000)

        let snapshot = await queue.snapshot()
        #expect(snapshot.runningCount == 2)
        #expect(extractor.maximumActiveCount == 2)

        extractor.release(3)
        try await waitUntil("all jobs succeeded") {
            try ["att1", "att2", "att3"].allSatisfy {
                try job(database, attachmentId: $0)?.status == "succeeded"
            }
        }
        #expect(extractor.maximumActiveCount <= 2)
        #expect(extractor.callCount == 3)
    }

    @Test func repeatedEnqueueDoesNotDuplicateRunningOrCompletedWork() async throws {
        let database = try makeDatabase()
        try seedAttachmentGraph(database, attachments: [
            attachment(id: "att1", filename: "invoice.txt", mime: "text/plain"),
        ])
        let byteStore = try makeByteStore()
        try byteStore.store.store(Data("Invoice total due Friday".utf8), for: key(attachmentId: "att1"))
        let extractor = BlockingAttachmentExtractor(result: completeExtractionResult)
        let queue = LocalAttachmentProcessingQueue(
            database: database,
            byteStore: byteStore.store,
            extractor: extractor,
            configuration: LocalAttachmentProcessingQueueConfiguration(maxConcurrentTasks: 1)
        )
        let request = LocalAttachmentProcessingRequest(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            filename: "invoice.txt",
            mimeType: "text/plain",
            sizeBytes: 24
        )

        try await queue.enqueue([request])
        #expect(extractor.waitForEntries(1))
        try await queue.enqueue([request])

        extractor.release(1)
        try await waitUntil("deduped job succeeded") {
            try job(database, attachmentId: "att1")?.status == "succeeded"
        }

        try await queue.enqueue([request])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(extractor.callCount == 1)
        #expect(try jobCount(database, attachmentId: "att1") == 1)
    }

    @Test func prioritizingAttachmentRaisesQueuedJobPriority() async throws {
        let database = try makeDatabase()
        try seedAttachmentGraph(database, attachments: [
            attachment(id: "att1", filename: "one.txt", mime: "text/plain"),
            attachment(id: "att2", filename: "two.txt", mime: "text/plain"),
        ])
        let byteStore = try makeByteStore()
        try byteStore.store.store(Data("Invoice one total due Friday".utf8), for: key(attachmentId: "att1"))
        try byteStore.store.store(Data("Invoice two total due Friday".utf8), for: key(attachmentId: "att2"))
        let extractor = BlockingAttachmentExtractor(result: completeExtractionResult)
        let queue = LocalAttachmentProcessingQueue(
            database: database,
            byteStore: byteStore.store,
            extractor: extractor,
            configuration: LocalAttachmentProcessingQueueConfiguration(maxConcurrentTasks: 1)
        )

        try await queue.enqueue([
            LocalAttachmentProcessingRequest(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                filename: "one.txt",
                mimeType: "text/plain"
            ),
            LocalAttachmentProcessingRequest(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att2",
                filename: "two.txt",
                mimeType: "text/plain"
            ),
        ])
        #expect(extractor.waitForEntries(1))

        try await queue.prioritizeAttachment(accountId: "a1", messageId: "m1", attachmentId: "att2")
        #expect(try job(database, attachmentId: "att2")?.priority == 100)

        extractor.release(1)
        #expect(extractor.waitForEntries(1))
        #expect(extractor.attachmentOrder == ["att1", "att2"])

        extractor.release(1)
        try await waitUntil("prioritized job succeeded") {
            try job(database, attachmentId: "att2")?.status == "succeeded"
        }
    }

    private var completeExtractionResult: AttachmentExtractionResult {
        AttachmentExtractionResult(
            status: .complete,
            extractedText: [
                AttachmentExtractedText(
                    text: "Invoice total is 42.00. Payment due Friday.",
                    locator: .byteRange(start: 0, end: 42)
                ),
            ]
        )
    }
}

private struct ByteStoreFixture {
    var rootURL: URL
    var store: LocalAttachmentByteStore
}

private func makeDatabase() throws -> AppDatabase {
    try AppDatabase.openInMemorySync()
}

private func makeByteStore() throws -> ByteStoreFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("AttachmentProcessingQueueTests-\(UUID().uuidString)", isDirectory: true)
    let store = try LocalAttachmentByteStore(rootURL: rootURL)
    return ByteStoreFixture(rootURL: rootURL, store: store)
}

private func seedAttachmentGraph(
    _ database: AppDatabase,
    attachments: [AttachmentRecord]
) throws {
    try database.dbQueue.write { db in
        try AccountRecord(id: "a1", email: "test@example.com", createdAt: 1).insert(db)
        try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2, messageCount: 1).insert(db)
        try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 2).insert(db)
        for attachment in attachments {
            try attachment.insert(db)
        }
    }
}

private func attachment(
    id: String,
    filename: String,
    mime: String
) -> AttachmentRecord {
    AttachmentRecord(
        id: id,
        messageId: "m1",
        accountId: "a1",
        filename: filename,
        mime: mime,
        sizeBytes: 4096
    )
}

private func key(attachmentId: String) -> AttachmentByteKey {
    AttachmentByteKey(accountId: "a1", messageId: "m1", attachmentId: attachmentId)
}

private func job(
    _ database: AppDatabase,
    attachmentId: String
) throws -> AttachmentProcessingJobRecord? {
    try database.dbQueue.read { db in
        try AttachmentProcessingJobRecord
            .filter(Column("account_id") == "a1")
            .filter(Column("message_id") == "m1")
            .filter(Column("attachment_id") == attachmentId)
            .fetchOne(db)
    }
}

private func jobCount(
    _ database: AppDatabase,
    attachmentId: String
) throws -> Int {
    try database.dbQueue.read { db in
        try AttachmentProcessingJobRecord
            .filter(Column("account_id") == "a1")
            .filter(Column("message_id") == "m1")
            .filter(Column("attachment_id") == attachmentId)
            .fetchCount(db)
    }
}

private func extraction(
    _ database: AppDatabase,
    attachmentId: String
) throws -> AttachmentExtractionRecord? {
    try database.dbQueue.read { db in
        try AttachmentExtractionRecord
            .filter(Column("account_id") == "a1")
            .filter(Column("message_id") == "m1")
            .filter(Column("attachment_id") == attachmentId)
            .fetchOne(db)
    }
}

private func extractionCount(
    _ database: AppDatabase,
    attachmentId: String
) throws -> Int {
    try database.dbQueue.read { db in
        try AttachmentExtractionRecord
            .filter(Column("account_id") == "a1")
            .filter(Column("message_id") == "m1")
            .filter(Column("attachment_id") == attachmentId)
            .fetchCount(db)
    }
}

private func chunkCount(
    _ database: AppDatabase,
    attachmentId: String
) throws -> Int {
    try database.dbQueue.read { db in
        try AttachmentChunkRecord
            .filter(Column("account_id") == "a1")
            .filter(Column("message_id") == "m1")
            .filter(Column("attachment_id") == attachmentId)
            .fetchCount(db)
    }
}

private func artifactCount(
    _ database: AppDatabase,
    attachmentId: String
) throws -> Int {
    try database.dbQueue.read { db in
        try AttachmentAIArtifactRecord
            .filter(Column("account_id") == "a1")
            .filter(Column("message_id") == "m1")
            .filter(Column("attachment_id") == attachmentId)
            .fetchCount(db)
    }
}

private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 3,
    condition: @escaping () throws -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try condition() {
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    throw LocalAttachmentProcessingQueueTestError.timeout(description)
}

private enum LocalAttachmentProcessingQueueTestError: Error {
    case timeout(String)
}

private final class AttachmentProcessingEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LocalAttachmentProcessingEvent] = []

    func record(_ event: LocalAttachmentProcessingEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }

    func contains(
        kind: LocalAttachmentProcessingEventKind,
        attachmentId: String
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.contains {
            $0.kind == kind && $0.attachmentId == attachmentId
        }
    }
}

private final class BlockingAttachmentExtractor: AttachmentExtractor, @unchecked Sendable {
    private let result: AttachmentExtractionResult
    private let entered = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var activeCount = 0
    private var maxActiveCount = 0
    private var calls = 0
    private var order: [String] = []

    init(result: AttachmentExtractionResult) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    var maximumActiveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return maxActiveCount
    }

    var attachmentOrder: [String] {
        lock.lock()
        defer { lock.unlock() }
        return order
    }

    func extract(_ input: AttachmentExtractionInput) -> AttachmentExtractionResult {
        lock.lock()
        calls += 1
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        if let attachmentId = input.key?.attachmentId {
            order.append(attachmentId)
        }
        lock.unlock()

        entered.signal()
        _ = releaseSemaphore.wait(timeout: .now() + 5)

        lock.lock()
        activeCount -= 1
        lock.unlock()
        return result
    }

    func waitForEntries(_ count: Int) -> Bool {
        for _ in 0..<count {
            guard entered.wait(timeout: .now() + 2) == .success else {
                return false
            }
        }
        return true
    }

    func release(_ count: Int) {
        for _ in 0..<count {
            releaseSemaphore.signal()
        }
    }
}
