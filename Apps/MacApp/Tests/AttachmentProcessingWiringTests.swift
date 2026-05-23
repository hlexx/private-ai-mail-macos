import AttachmentKit
import AttachmentRAG
import Foundation
import GRDB
import InboxFeature
import Persistence
import Testing
@testable import ThreadFeature

@testable import PrivateAIMail

@Suite("Attachment processing wiring")
struct AttachmentProcessingWiringTests {
    @MainActor
    @Test func selectingThreadStartsAttachmentProcessing() async {
        let recorder = AttachmentProcessingRecorder()
        let task = AttachmentProcessingActionRouter.selectedThreadTask(
            selectedThreadID: "thread-1",
            threads: [Self.threadRow(id: "thread-1", accountId: "acc-1")],
            service: recorder.service(),
            onFailure: { message in
                Issue.record("Unexpected failure message: \(message)")
            }
        )

        await task.value

        #expect(await recorder.startedSelections == [
            AttachmentProcessingRecorder.Selection(accountId: "acc-1", messageId: "thread-1"),
        ])
        #expect(await recorder.cancelCount == 0)
    }

    @MainActor
    @Test func clearingThreadSelectionCancelsAttachmentProcessing() async {
        let recorder = AttachmentProcessingRecorder()
        let task = AttachmentProcessingActionRouter.selectedThreadTask(
            selectedThreadID: nil,
            threads: [Self.threadRow(id: "thread-1", accountId: "acc-1")],
            service: recorder.service(),
            onFailure: { message in
                Issue.record("Unexpected failure message: \(message)")
            }
        )

        await task.value

        #expect(await recorder.cancelCount == 1)
        #expect(await recorder.startedSelections.isEmpty)
    }

    @MainActor
    @Test func summarizeActionPrioritizesSelectedAttachment() async {
        let recorder = AttachmentProcessingRecorder()
        let attachment = Self.attachmentInfo(
            id: "att-1",
            accountId: "acc-1",
            messageId: "msg-1"
        )
        let task = AttachmentProcessingActionRouter.prioritizeAttachmentTask(
            attachment: attachment,
            service: recorder.service(),
            onFailure: { message in
                Issue.record("Unexpected failure message: \(message)")
            }
        )

        await task.value

        #expect(await recorder.prioritizedAttachments == [
            AttachmentProcessingRecorder.Attachment(accountId: "acc-1", messageId: "msg-1", attachmentId: "att-1"),
        ])
    }

    @MainActor
    @Test func processingFailureShowsUnderstandableMessage() async {
        let recorder = AttachmentProcessingRecorder(startError: AttachmentProcessingTestError.failed)
        var messages: [String] = []
        let task = AttachmentProcessingActionRouter.selectedThreadTask(
            selectedThreadID: "thread-1",
            threads: [Self.threadRow(id: "thread-1", accountId: "acc-1")],
            service: recorder.service(),
            onFailure: { message in
                messages.append(message)
            }
        )

        await task.value

        #expect(messages == [AttachmentProcessingActionRouter.startFailureMessage])
    }

    @Test func disabledAttachmentActionsStayDisabledWithoutLocalFile() {
        let attachment = Self.attachmentInfo(
            id: "att-1",
            accountId: "acc-1",
            messageId: "msg-1"
        )

        #expect(attachment.localFileStatusText == "No local file yet")
        #expect(attachment.canPreviewAttachment(hasHandler: true) == false)
        #expect(attachment.canSummarizeAttachment(hasHandler: true) == false)
    }

    @MainActor
    @Test func liveServiceWritesWaitingStateWhenLocalBytesAreMissing() async throws {
        let database = try AppDatabase.openInMemorySync()
        try Self.seedAttachmentGraph(
            database,
            attachment: AttachmentRecord(
                id: "att-1",
                messageId: "msg-1",
                accountId: "acc-1",
                filename: "invoice.pdf",
                mime: "application/pdf",
                sizeBytes: 4096
            )
        )
        let rootURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let byteStore = try LocalAttachmentByteStore(rootURL: rootURL)
        let queue = LocalAttachmentProcessingQueue(database: database, byteStore: byteStore)
        let service = AttachmentProcessingService(queue: queue)
        let store = ThreadStore(db: database)
        store.observe(threadId: "thread-1", accountId: "acc-1")
        defer { store.stopObserving() }

        _ = try await service.replaceActiveMessage(accountId: "acc-1", messageId: "msg-1")

        try await Self.waitUntil("waiting local bytes") {
            try Self.job(database, attachmentId: "att-1")?.status == "waiting_for_local_file"
        }
        try await Self.waitUntil("thread store waiting state") {
            store.attachments.first?.localFileStatusText == "No local file yet"
                && store.attachments.first?.extractionStatusText == "Text not extracted"
        }
    }

    @MainActor
    @Test func liveServiceWritesUnsupportedStateWithoutBreakingThreadDisplay() async throws {
        let database = try AppDatabase.openInMemorySync()
        try Self.seedAttachmentGraph(
            database,
            attachment: AttachmentRecord(
                id: "att-1",
                messageId: "msg-1",
                accountId: "acc-1",
                filename: "proposal.docx",
                mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                sizeBytes: 4096
            )
        )
        let rootURL = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let byteStore = try LocalAttachmentByteStore(rootURL: rootURL)
        try byteStore.store(Data("not a real docx".utf8), for: AttachmentByteKey(
            accountId: "acc-1",
            messageId: "msg-1",
            attachmentId: "att-1"
        ))
        let queue = LocalAttachmentProcessingQueue(database: database, byteStore: byteStore)
        let service = AttachmentProcessingService(queue: queue)
        let store = ThreadStore(db: database)
        store.observe(threadId: "thread-1", accountId: "acc-1")
        defer { store.stopObserving() }

        _ = try await service.replaceActiveMessage(accountId: "acc-1", messageId: "msg-1")

        try await Self.waitUntil("unsupported local attachment") {
            try Self.job(database, attachmentId: "att-1")?.status == "unsupported"
        }
        try await Self.waitUntil("thread store unsupported state") {
            guard let attachment = store.attachments.first else { return false }
            return attachment.extractionStatusText.contains("Format not supported")
                && attachment.summaryStatusText == "Summary unavailable for unsupported format"
        }
    }

    private static func threadRow(id: String, accountId: String) -> ThreadRow {
        ThreadRow(record: ThreadRecord(
            id: id,
            accountId: accountId,
            subject: "Thread \(id)",
            snippet: "snippet",
            lastMessageAt: 1,
            messageCount: 1,
            hasUnread: 0
        ))
    }

    private static func attachmentInfo(
        id: String,
        accountId: String,
        messageId: String
    ) -> AttachmentInfo {
        AttachmentInfo(
            id: id,
            accountId: accountId,
            messageId: messageId,
            filename: "invoice.pdf",
            sizeBytes: 4096,
            mime: "application/pdf"
        )
    }

    private static func seedAttachmentGraph(
        _ database: AppDatabase,
        attachment: AttachmentRecord
    ) throws {
        try database.dbQueue.write { db in
            try AccountRecord(id: "acc-1", email: "test@example.com", createdAt: 1).insert(db)
            try ThreadRecord(
                id: "thread-1",
                accountId: "acc-1",
                subject: "Attachment thread",
                snippet: "Attachment",
                lastMessageAt: 2,
                messageCount: 1
            ).insert(db)
            try MessageRecord(
                id: "msg-1",
                threadId: "thread-1",
                accountId: "acc-1",
                sentAt: 2
            ).insert(db)
            try attachment.insert(db)
        }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAppAttachmentProcessing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private static func job(
        _ database: AppDatabase,
        attachmentId: String
    ) throws -> AttachmentProcessingJobRecord? {
        try database.dbQueue.read { db in
            try AttachmentProcessingJobRecord
                .filter(Column("account_id") == "acc-1")
                .filter(Column("message_id") == "msg-1")
                .filter(Column("attachment_id") == attachmentId)
                .fetchOne(db)
        }
    }

    @MainActor
    private static func waitUntil(
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
        throw AttachmentProcessingTestError.timeout(description)
    }
}

private actor AttachmentProcessingRecorder {
    struct Selection: Equatable {
        var accountId: String
        var messageId: String
    }

    struct Attachment: Equatable {
        var accountId: String
        var messageId: String
        var attachmentId: String
    }

    private let startError: (any Error)?
    private let prioritizeError: (any Error)?
    private(set) var startedSelections: [Selection] = []
    private(set) var cancelCount = 0
    private(set) var prioritizedAttachments: [Attachment] = []

    init(
        startError: (any Error)? = nil,
        prioritizeError: (any Error)? = nil
    ) {
        self.startError = startError
        self.prioritizeError = prioritizeError
    }

    nonisolated func service() -> AttachmentProcessingService {
        AttachmentProcessingService(
            replaceActiveMessage: { [weak self] accountId, messageId in
                guard let self else { return 0 }
                return try await self.replaceActiveMessage(accountId: accountId, messageId: messageId)
            },
            cancelAll: { [weak self] in
                await self?.cancelAll()
            },
            prioritizeAttachment: { [weak self] attachment in
                try await self?.prioritizeAttachment(attachment)
            }
        )
    }

    private func replaceActiveMessage(accountId: String, messageId: String) throws -> Int {
        if let startError {
            throw startError
        }
        startedSelections.append(Selection(accountId: accountId, messageId: messageId))
        return 1
    }

    private func cancelAll() {
        cancelCount += 1
    }

    private func prioritizeAttachment(_ attachment: AttachmentInfo) throws {
        if let prioritizeError {
            throw prioritizeError
        }
        prioritizedAttachments.append(Attachment(
            accountId: attachment.accountId,
            messageId: attachment.messageId,
            attachmentId: attachment.id
        ))
    }
}

private enum AttachmentProcessingTestError: Error {
    case failed
    case timeout(String)
}
