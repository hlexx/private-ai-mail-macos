import AttachmentKit
import CryptoKit
import Foundation
import GRDB
import OSLog
import Persistence

public enum LocalAttachmentProcessingPriority: Equatable, Sendable {
    case normal
    case selected
    case custom(Int)

    func value(configuration: LocalAttachmentProcessingQueueConfiguration) -> Int {
        switch self {
        case .normal:
            return configuration.normalPriority
        case .selected:
            return configuration.selectedPriority
        case let .custom(value):
            return value
        }
    }
}

public struct LocalAttachmentProcessingQueueConfiguration: Equatable, Sendable {
    public var maxConcurrentTasks: Int
    public var extractionVersion: Int
    public var normalPriority: Int
    public var selectedPriority: Int

    public init(
        maxConcurrentTasks: Int = 2,
        extractionVersion: Int = 1,
        normalPriority: Int = 0,
        selectedPriority: Int = 100
    ) {
        precondition(maxConcurrentTasks > 0)
        precondition(extractionVersion > 0)
        self.maxConcurrentTasks = maxConcurrentTasks
        self.extractionVersion = extractionVersion
        self.normalPriority = normalPriority
        self.selectedPriority = selectedPriority
    }

    var extractionVersionLabel: String {
        "extract-v\(extractionVersion)"
    }
}

public struct LocalAttachmentProcessingRequest: Equatable, Sendable {
    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var filename: String?
    public var mimeType: String?
    public var sizeBytes: Int?

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        filename: String? = nil,
        mimeType: String? = nil,
        sizeBytes: Int? = nil
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }

    public init(record: AttachmentRecord) {
        self.init(
            accountId: record.accountId,
            messageId: record.messageId,
            attachmentId: record.id,
            filename: record.filename,
            mimeType: record.mime,
            sizeBytes: record.sizeBytes
        )
    }

    var byteKey: AttachmentByteKey {
        AttachmentByteKey(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId
        )
    }
}

public enum LocalAttachmentProcessingEventKind: String, Equatable, Sendable {
    case queued
    case started
    case completed
    case skippedMissingBytes
    case cancelled
    case failed
}

public struct LocalAttachmentProcessingEvent: Equatable, Sendable {
    public var kind: LocalAttachmentProcessingEventKind
    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var status: String
    public var priority: Int
    public var errorCode: String?

    public init(
        kind: LocalAttachmentProcessingEventKind,
        accountId: String,
        messageId: String,
        attachmentId: String,
        status: String,
        priority: Int,
        errorCode: String? = nil
    ) {
        self.kind = kind
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.status = status
        self.priority = priority
        self.errorCode = errorCode
    }
}

public typealias LocalAttachmentProcessingEventSink = @Sendable (LocalAttachmentProcessingEvent) -> Void

public struct LocalAttachmentProcessingQueueSnapshot: Equatable, Sendable {
    public var pendingCount: Int
    public var runningCount: Int

    public init(pendingCount: Int, runningCount: Int) {
        self.pendingCount = pendingCount
        self.runningCount = runningCount
    }
}

public actor LocalAttachmentProcessingQueue {
    public static let jobKind = "local_attachment_processing"

    private static let logger = Logger(subsystem: "PrivateAIMail", category: "AttachmentProcessing")

    private let database: AppDatabase
    private let byteStore: any AttachmentByteStore
    private let extractor: any AttachmentExtractor
    private let orchestrator: AttachmentSummaryOrchestrator
    private let configuration: LocalAttachmentProcessingQueueConfiguration
    private let eventSink: LocalAttachmentProcessingEventSink?
    private let now: @Sendable () -> Int

    private var pending: [QueuedAttachmentProcessingRequest] = []
    private var running: [AttachmentProcessingKey: RunningAttachmentProcessingTask] = [:]
    private var sequence = 0

    public init(
        database: AppDatabase,
        byteStore: any AttachmentByteStore,
        extractor: any AttachmentExtractor = PlatformAttachmentExtractor(),
        orchestrator: AttachmentSummaryOrchestrator? = nil,
        configuration: LocalAttachmentProcessingQueueConfiguration = LocalAttachmentProcessingQueueConfiguration(),
        eventSink: LocalAttachmentProcessingEventSink? = nil,
        now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }
    ) {
        self.database = database
        self.byteStore = byteStore
        self.extractor = extractor
        let cache = PersistenceAttachmentRAGCache(database: database)
        self.orchestrator = orchestrator ?? AttachmentSummaryOrchestrator(cache: cache)
        self.configuration = configuration
        self.eventSink = eventSink
        self.now = now
    }

    @discardableResult
    public func replaceActiveMessage(accountId: String, messageId: String) async throws -> Int {
        await cancelAll()
        return try await enqueueMessage(accountId: accountId, messageId: messageId)
    }

    @discardableResult
    public func enqueueMessage(accountId: String, messageId: String) async throws -> Int {
        let records = try await fetchAttachmentRecords(accountId: accountId, messageId: messageId)
        try await enqueue(records.map(LocalAttachmentProcessingRequest.init), priority: .normal)
        return records.count
    }

    public func prioritizeAttachment(
        accountId: String,
        messageId: String,
        attachmentId: String
    ) async throws {
        guard let record = try await fetchAttachmentRecord(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId
        ) else {
            return
        }
        try await enqueue([LocalAttachmentProcessingRequest(record: record)], priority: .selected)
    }

    public func enqueue(
        _ requests: [LocalAttachmentProcessingRequest],
        priority: LocalAttachmentProcessingPriority = .normal
    ) async throws {
        for request in requests {
            try await enqueue(request, priority: priority.value(configuration: configuration))
        }
        startWorkersIfNeeded()
    }

    public func cancelAll() async {
        let pendingItems = pending
        let runningItems = running

        pending.removeAll()

        for item in runningItems.values {
            item.task.cancel()
        }

        for item in pendingItems {
            await markCancelled(item.request, priority: item.priority)
            emit(event: .init(
                kind: .cancelled,
                accountId: item.request.accountId,
                messageId: item.request.messageId,
                attachmentId: item.request.attachmentId,
                status: AttachmentProcessingStatus.cancelled.rawValue,
                priority: item.priority,
                errorCode: AttachmentProcessingErrorCode.cancelled.rawValue
            ))
        }

        for item in runningItems.values.map(\.item) {
            await markCancelled(item.request, priority: item.priority)
        }
    }

    public func cancelMessage(accountId: String, messageId: String) async {
        let pendingToCancel = pending.filter {
            $0.request.accountId == accountId && $0.request.messageId == messageId
        }
        pending.removeAll {
            $0.request.accountId == accountId && $0.request.messageId == messageId
        }
        for item in pendingToCancel {
            await markCancelled(item.request, priority: item.priority)
            emit(event: .init(
                kind: .cancelled,
                accountId: item.request.accountId,
                messageId: item.request.messageId,
                attachmentId: item.request.attachmentId,
                status: AttachmentProcessingStatus.cancelled.rawValue,
                priority: item.priority,
                errorCode: AttachmentProcessingErrorCode.cancelled.rawValue
            ))
        }

        let runningToCancel = running.filter {
            $0.key.accountId == accountId && $0.key.messageId == messageId
        }
        for item in runningToCancel.values {
            item.task.cancel()
            await markCancelled(item.item.request, priority: item.item.priority)
        }
        startWorkersIfNeeded()
    }

    public func snapshot() -> LocalAttachmentProcessingQueueSnapshot {
        LocalAttachmentProcessingQueueSnapshot(
            pendingCount: pending.count,
            runningCount: running.count
        )
    }

    private func enqueue(_ request: LocalAttachmentProcessingRequest, priority: Int) async throws {
        let key = AttachmentProcessingKey(request)
        if var item = pending.first(where: { $0.key == key }) {
            item.priority = max(item.priority, priority)
            replacePendingItem(item)
            try await upsertJob(
                request,
                status: .queued,
                priority: item.priority,
                errorCode: nil,
                errorMessage: nil,
                incrementAttempt: false
            )
            emitQueued(request, priority: item.priority)
            return
        }

        if var item = running[key] {
            let updatedPriority = max(item.item.priority, priority)
            item.item.priority = updatedPriority
            running[key] = item
            try await upsertJob(
                request,
                status: .running,
                priority: updatedPriority,
                errorCode: nil,
                errorMessage: nil,
                incrementAttempt: false
            )
            emitQueued(request, priority: updatedPriority)
            return
        }

        guard try await shouldEnqueue(request) else {
            return
        }

        sequence += 1
        let item = QueuedAttachmentProcessingRequest(
            request: request,
            key: key,
            priority: priority,
            sequence: sequence
        )
        pending.append(item)
        try await upsertJob(
            request,
            status: .queued,
            priority: priority,
            errorCode: nil,
            errorMessage: nil,
            incrementAttempt: false
        )
        emitQueued(request, priority: priority)
    }

    private func startWorkersIfNeeded() {
        sortPending()
        while running.count < configuration.maxConcurrentTasks, !pending.isEmpty {
            let item = pending.removeFirst()

            emit(event: .init(
                kind: .started,
                accountId: item.request.accountId,
                messageId: item.request.messageId,
                attachmentId: item.request.attachmentId,
                status: AttachmentProcessingStatus.running.rawValue,
                priority: item.priority
            ))

            let task = Task.detached { [
                database,
                byteStore,
                extractor,
                orchestrator,
                configuration,
                now
            ] in
                await Task.yield()
                let outcome = await Self.process(
                    item: item,
                    database: database,
                    byteStore: byteStore,
                    extractor: extractor,
                    orchestrator: orchestrator,
                    configuration: configuration,
                    now: now
                )
                await self.finish(item, outcome: outcome)
            }
            running[item.key] = RunningAttachmentProcessingTask(task: task, item: item)
        }
    }

    private func finish(
        _ item: QueuedAttachmentProcessingRequest,
        outcome: AttachmentProcessingOutcome
    ) {
        let finalItem = running.removeValue(forKey: item.key)?.item ?? item
        emit(event: .init(
            kind: outcome.eventKind,
            accountId: finalItem.request.accountId,
            messageId: finalItem.request.messageId,
            attachmentId: finalItem.request.attachmentId,
            status: outcome.status.rawValue,
            priority: finalItem.priority,
            errorCode: outcome.errorCode
        ))
        startWorkersIfNeeded()
    }

    private func replacePendingItem(_ item: QueuedAttachmentProcessingRequest) {
        guard let index = pending.firstIndex(where: { $0.key == item.key }) else {
            return
        }
        pending[index] = item
        sortPending()
    }

    private func sortPending() {
        pending.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.sequence < rhs.sequence
        }
    }

    private func emitQueued(_ request: LocalAttachmentProcessingRequest, priority: Int) {
        emit(event: .init(
            kind: .queued,
            accountId: request.accountId,
            messageId: request.messageId,
            attachmentId: request.attachmentId,
            status: AttachmentProcessingStatus.queued.rawValue,
            priority: priority
        ))
    }

    private func emit(event: LocalAttachmentProcessingEvent) {
        eventSink?(event)
        Self.logger.info(
            """
            attachment_processing event=\(event.kind.rawValue, privacy: .public) \
            status=\(event.status, privacy: .public) \
            priority=\(event.priority, privacy: .public) \
            error=\(event.errorCode ?? "none", privacy: .public) \
            attachment=\(event.attachmentId, privacy: .private(mask: .hash))
            """
        )
    }

    private func fetchAttachmentRecords(
        accountId: String,
        messageId: String
    ) async throws -> [AttachmentRecord] {
        try await Task.detached { [database] in
            try database.dbQueue.read { db in
                try AttachmentRecord
                    .filter(Column("account_id") == accountId)
                    .filter(Column("message_id") == messageId)
                    .fetchAll(db)
                    .filter { !($0.contentId != nil && $0.dataBase64 != nil) }
            }
        }.value
    }

    private func fetchAttachmentRecord(
        accountId: String,
        messageId: String,
        attachmentId: String
    ) async throws -> AttachmentRecord? {
        try await Task.detached { [database] in
            try database.dbQueue.read { db in
                try AttachmentRecord
                    .filter(Column("account_id") == accountId)
                    .filter(Column("message_id") == messageId)
                    .filter(Column("id") == attachmentId)
                    .fetchOne(db)
            }
        }.value
    }

    private func shouldEnqueue(_ request: LocalAttachmentProcessingRequest) async throws -> Bool {
        try await Task.detached { [database, configuration] in
            try database.dbQueue.read { db in
                let existingJob = try AttachmentProcessingJobRecord.fetchOne(
                    db,
                    key: Self.jobID(for: request)
                )
                guard existingJob?.status != AttachmentProcessingStatus.succeeded.rawValue else {
                    let extraction = try AttachmentExtractionRecord
                        .filter(Column("account_id") == request.accountId)
                        .filter(Column("message_id") == request.messageId)
                        .filter(Column("attachment_id") == request.attachmentId)
                        .filter(Column("extraction_version") == configuration.extractionVersion)
                        .fetchOne(db)
                    return extraction == nil
                }
                return true
            }
        }.value
    }

    private func upsertJob(
        _ request: LocalAttachmentProcessingRequest,
        status: AttachmentProcessingStatus,
        priority: Int,
        errorCode: String?,
        errorMessage: String?,
        incrementAttempt: Bool
    ) async throws {
        let timestamp = now()
        try await Task.detached { [database] in
            try Self.upsertJob(
                request,
                status: status,
                priority: priority,
                errorCode: errorCode,
                errorMessage: errorMessage,
                incrementAttempt: incrementAttempt,
                timestamp: timestamp,
                database: database
            )
        }.value
    }

    private func markCancelled(
        _ request: LocalAttachmentProcessingRequest,
        priority: Int
    ) async {
        let timestamp = now()
        try? await Task.detached { [database, configuration] in
            try Self.markCancelled(
                request,
                priority: priority,
                timestamp: timestamp,
                configuration: configuration,
                database: database
            )
        }.value
    }

    private static func process(
        item: QueuedAttachmentProcessingRequest,
        database: AppDatabase,
        byteStore: any AttachmentByteStore,
        extractor: any AttachmentExtractor,
        orchestrator: AttachmentSummaryOrchestrator,
        configuration: LocalAttachmentProcessingQueueConfiguration,
        now: @Sendable () -> Int
    ) async -> AttachmentProcessingOutcome {
        let request = item.request

        do {
            try Task.checkCancellation()
            try upsertJob(
                request,
                status: .running,
                priority: item.priority,
                errorCode: nil,
                errorMessage: nil,
                incrementAttempt: true,
                timestamp: now(),
                database: database
            )

            let data = try byteStore.read(for: request.byteKey)
            guard let data else {
                try upsertJob(
                    request,
                    status: .waitingForLocalFile,
                    priority: item.priority,
                    errorCode: AttachmentProcessingErrorCode.missingLocalFile.rawValue,
                    errorMessage: "Attachment bytes are not available in local storage.",
                    incrementAttempt: false,
                    timestamp: now(),
                    database: database
                )
                return .init(status: .waitingForLocalFile, eventKind: .skippedMissingBytes)
            }

            try Task.checkCancellation()
            let contentHash = contentHash(for: data)
            try upsertExtraction(
                request,
                result: nil,
                status: .running,
                contentHash: contentHash,
                byteCount: data.count,
                configuration: configuration,
                timestamp: now(),
                database: database
            )

            let extractionResult = extractor.extract(AttachmentExtractionInput(
                key: request.byteKey,
                filename: request.filename,
                mimeType: request.mimeType,
                data: data
            ))

            try Task.checkCancellation()
            try upsertExtraction(
                request,
                result: extractionResult,
                status: AttachmentProcessingStatus(extractionStatus: extractionResult.status),
                contentHash: contentHash,
                byteCount: data.count,
                configuration: configuration,
                timestamp: now(),
                database: database
            )

            switch extractionResult.status {
            case .unsupported:
                let failure = extractionResult.failures.first
                try upsertJob(
                    request,
                    status: .unsupported,
                    priority: item.priority,
                    errorCode: failure?.code.rawValue ?? AttachmentProcessingErrorCode.unsupported.rawValue,
                    errorMessage: failure?.userFacingReason,
                    incrementAttempt: false,
                    timestamp: now(),
                    database: database
                )
                return .init(
                    status: .unsupported,
                    eventKind: .completed,
                    errorCode: failure?.code.rawValue ?? AttachmentProcessingErrorCode.unsupported.rawValue
                )
            case .failed:
                let failure = extractionResult.failures.first
                try upsertJob(
                    request,
                    status: .failed,
                    priority: item.priority,
                    errorCode: failure?.code.rawValue ?? AttachmentProcessingErrorCode.extractionFailed.rawValue,
                    errorMessage: failure?.userFacingReason,
                    incrementAttempt: false,
                    timestamp: now(),
                    database: database
                )
                return .init(
                    status: .failed,
                    eventKind: .failed,
                    errorCode: failure?.code.rawValue ?? AttachmentProcessingErrorCode.extractionFailed.rawValue
                )
            case .complete, .incomplete:
                break
            }

            try Task.checkCancellation()
            let summaryStatus = await orchestrator.summarize(AttachmentSummaryRequest(
                scope: AttachmentRAGCacheScope(
                    accountId: request.accountId,
                    messageId: request.messageId,
                    attachmentId: request.attachmentId,
                    extractionVersion: configuration.extractionVersion
                ),
                extractionVersion: configuration.extractionVersionLabel,
                extractionResult: extractionResult,
                createdAt: now()
            ))

            try Task.checkCancellation()
            return try completeJob(
                request,
                summaryStatus: summaryStatus,
                priority: item.priority,
                timestamp: now(),
                database: database
            )
        } catch is CancellationError {
            try? markCancelled(
                request,
                priority: item.priority,
                timestamp: now(),
                configuration: configuration,
                database: database
            )
            return .init(
                status: .cancelled,
                eventKind: .cancelled,
                errorCode: AttachmentProcessingErrorCode.cancelled.rawValue
            )
        } catch {
            try? upsertJob(
                request,
                status: .failed,
                priority: item.priority,
                errorCode: AttachmentProcessingErrorCode.processingFailed.rawValue,
                errorMessage: "Local attachment processing failed.",
                incrementAttempt: false,
                timestamp: now(),
                database: database
            )
            return .init(
                status: .failed,
                eventKind: .failed,
                errorCode: AttachmentProcessingErrorCode.processingFailed.rawValue
            )
        }
    }

    private static func completeJob(
        _ request: LocalAttachmentProcessingRequest,
        summaryStatus: AttachmentSummaryStatus,
        priority: Int,
        timestamp: Int,
        database: AppDatabase
    ) throws -> AttachmentProcessingOutcome {
        switch summaryStatus {
        case .complete:
            try upsertJob(
                request,
                status: .succeeded,
                priority: priority,
                errorCode: nil,
                errorMessage: nil,
                incrementAttempt: false,
                timestamp: timestamp,
                database: database
            )
            return .init(status: .succeeded, eventKind: .completed)
        case let .incomplete(_, reason, _):
            try upsertJob(
                request,
                status: .incomplete,
                priority: priority,
                errorCode: reason.rawValue,
                errorMessage: "Attachment summary is incomplete.",
                incrementAttempt: false,
                timestamp: timestamp,
                database: database
            )
            return .init(status: .incomplete, eventKind: .completed, errorCode: reason.rawValue)
        case let .unsupported(reason):
            try upsertJob(
                request,
                status: .unsupported,
                priority: priority,
                errorCode: reason.rawValue,
                errorMessage: "Attachment summary is unsupported for this extraction.",
                incrementAttempt: false,
                timestamp: timestamp,
                database: database
            )
            return .init(status: .unsupported, eventKind: .completed, errorCode: reason.rawValue)
        case let .failed(failure):
            try upsertJob(
                request,
                status: .failed,
                priority: priority,
                errorCode: failure.code.rawValue,
                errorMessage: "Attachment summary generation failed.",
                incrementAttempt: false,
                timestamp: timestamp,
                database: database
            )
            return .init(status: .failed, eventKind: .failed, errorCode: failure.code.rawValue)
        }
    }

    private static func upsertJob(
        _ request: LocalAttachmentProcessingRequest,
        status: AttachmentProcessingStatus,
        priority: Int,
        errorCode: String?,
        errorMessage: String?,
        incrementAttempt: Bool,
        timestamp: Int,
        database: AppDatabase
    ) throws {
        try database.dbQueue.write { db in
            var record = try AttachmentProcessingJobRecord.fetchOne(db, key: jobID(for: request))
                ?? AttachmentProcessingJobRecord(
                    id: jobID(for: request),
                    accountId: request.accountId,
                    messageId: request.messageId,
                    attachmentId: request.attachmentId,
                    jobKind: jobKind,
                    status: status.rawValue,
                    priority: priority,
                    attemptCount: 0,
                    availableAt: timestamp,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )

            record.status = status.rawValue
            record.priority = max(record.priority, priority)
            record.updatedAt = timestamp
            record.lastErrorCode = errorCode
            record.lastErrorMessage = errorMessage
            if incrementAttempt {
                record.attemptCount += 1
            }
            try record.save(db)
        }
    }

    private static func upsertExtraction(
        _ request: LocalAttachmentProcessingRequest,
        result: AttachmentExtractionResult?,
        status: AttachmentProcessingStatus,
        contentHash: String,
        byteCount: Int,
        configuration: LocalAttachmentProcessingQueueConfiguration,
        timestamp: Int,
        database: AppDatabase
    ) throws {
        let failure = result?.failures.first
        let completedAt: Int? = status == .running ? nil : timestamp
        try database.dbQueue.write { db in
            try AttachmentExtractionRecord(
                accountId: request.accountId,
                messageId: request.messageId,
                attachmentId: request.attachmentId,
                extractionVersion: configuration.extractionVersion,
                status: status.rawValue,
                contentHash: contentHash,
                mime: request.mimeType,
                filename: request.filename,
                byteCount: byteCount,
                createdAt: timestamp,
                updatedAt: timestamp,
                completedAt: completedAt,
                errorCode: failure?.code.rawValue,
                errorMessage: failure?.userFacingReason
            ).save(db)
        }
    }

    private static func markCancelled(
        _ request: LocalAttachmentProcessingRequest,
        priority: Int,
        timestamp: Int,
        configuration: LocalAttachmentProcessingQueueConfiguration,
        database: AppDatabase
    ) throws {
        try upsertJob(
            request,
            status: .cancelled,
            priority: priority,
            errorCode: AttachmentProcessingErrorCode.cancelled.rawValue,
            errorMessage: "Local attachment processing was cancelled.",
            incrementAttempt: false,
            timestamp: timestamp,
            database: database
        )

        try database.dbQueue.write { db in
            if var record = try AttachmentExtractionRecord
                .filter(Column("account_id") == request.accountId)
                .filter(Column("message_id") == request.messageId)
                .filter(Column("attachment_id") == request.attachmentId)
                .filter(Column("extraction_version") == configuration.extractionVersion)
                .fetchOne(db) {
                record.status = AttachmentProcessingStatus.cancelled.rawValue
                record.updatedAt = timestamp
                record.completedAt = timestamp
                record.errorCode = AttachmentProcessingErrorCode.cancelled.rawValue
                record.errorMessage = "Local attachment extraction was cancelled."
                try record.save(db)
            }
        }
    }

    private static func contentHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func jobID(for request: LocalAttachmentProcessingRequest) -> String {
        let payload = [
            request.accountId,
            request.messageId,
            request.attachmentId,
            jobKind,
        ]
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
        let digest = SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "attachment-local-processing:v1:\(digest)"
    }
}

private struct QueuedAttachmentProcessingRequest: Sendable {
    var request: LocalAttachmentProcessingRequest
    var key: AttachmentProcessingKey
    var priority: Int
    var sequence: Int
}

private struct RunningAttachmentProcessingTask: Sendable {
    var task: Task<Void, Never>
    var item: QueuedAttachmentProcessingRequest
}

private struct AttachmentProcessingKey: Hashable, Sendable {
    var accountId: String
    var messageId: String
    var attachmentId: String

    init(_ request: LocalAttachmentProcessingRequest) {
        self.accountId = request.accountId
        self.messageId = request.messageId
        self.attachmentId = request.attachmentId
    }
}

private enum AttachmentProcessingStatus: String, Sendable {
    case queued
    case running
    case complete
    case incomplete
    case unsupported
    case failed
    case waitingForLocalFile = "waiting_for_local_file"
    case succeeded
    case cancelled

    init(extractionStatus: AttachmentExtractionStatus) {
        switch extractionStatus {
        case .complete:
            self = .complete
        case .incomplete:
            self = .incomplete
        case .unsupported:
            self = .unsupported
        case .failed:
            self = .failed
        }
    }
}

private enum AttachmentProcessingErrorCode: String {
    case cancelled
    case extractionFailed = "extraction_failed"
    case missingLocalFile = "missing_local_file"
    case processingFailed = "processing_failed"
    case unsupported
}

private struct AttachmentProcessingOutcome: Sendable {
    var status: AttachmentProcessingStatus
    var eventKind: LocalAttachmentProcessingEventKind
    var errorCode: String?

    init(
        status: AttachmentProcessingStatus,
        eventKind: LocalAttachmentProcessingEventKind,
        errorCode: String? = nil
    ) {
        self.status = status
        self.eventKind = eventKind
        self.errorCode = errorCode
    }
}
