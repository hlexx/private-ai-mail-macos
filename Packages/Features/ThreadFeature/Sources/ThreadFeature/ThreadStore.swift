import Foundation
import AttachmentRAG
import GRDB
import Observation
import Persistence

public struct InlineAttachment: Sendable {
    public let contentId: String
    public let mime: String
    public let dataBase64: String
}

public struct MessageRow: Identifiable, Sendable {
    public let id: String
    public let threadId: String
    public let messageIdHeader: String?
    public let fromAddr: String
    public let toAddr: String?
    public let ccAddr: String?
    public let sentAt: Date
    public let snippet: String
    public let bodyText: String
    public let bodyHtml: String?
    public let flags: Int
    public let inlineAttachments: [InlineAttachment]

    public var isSentByMe: Bool {
        (flags & MessageRecord.sentByMe) != 0
    }

    /// Best available plain text for language detection and translation input.
    /// Falls back: bodyText -> HTML-stripped -> snippet.
    @MainActor public var bestPlainText: String {
        if let text = bodyHtml, !text.isEmpty, bodyText == snippet || bodyText.isEmpty {
            return MessageBodyView.htmlToPlainText(text) ?? bodyText
        }
        return bodyText
    }

    public init(record: MessageRecord, inlineAttachments: [InlineAttachment] = []) {
        self.id = record.id
        self.threadId = record.threadId
        self.messageIdHeader = record.messageIdHeader
        self.fromAddr = record.fromAddr ?? "(unknown)"
        self.toAddr = record.toAddr
        self.ccAddr = record.ccAddr
        self.sentAt = Date(timeIntervalSince1970: TimeInterval(record.sentAt))
        self.snippet = record.snippet ?? ""
        self.bodyText = record.bodyText ?? record.snippet ?? ""
        self.bodyHtml = record.bodyHtml
        self.flags = record.flags
        self.inlineAttachments = inlineAttachments
    }

    public var senderName: String {
        Self.extractName(from: fromAddr)
    }

    static func extractName(from addr: String) -> String {
        let trimmed = addr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "?" }
        if let angleBracket = trimmed.firstIndex(of: "<") {
            let name = trimmed[trimmed.startIndex..<angleBracket]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
        }
        if let at = trimmed.firstIndex(of: "@") {
            return String(trimmed[trimmed.startIndex..<at])
        }
        return trimmed
    }
}

public enum AttachmentLocalFileState: Equatable, Sendable {
    case waitingForLocalFile
    case available(byteCount: Int?, contentHash: String?)
}

public enum AttachmentExtractionDisplayState: Equatable, Sendable {
    case waitingForLocalFile
    case pending(status: String?)
    case running(status: String)
    case succeeded(version: Int, contentHash: String?)
    case unsupported(code: String?, message: String?)
    case failed(code: String?, message: String?)
}

public struct AttachmentProcessingDisplayState: Equatable, Sendable {
    public let jobKind: String
    public let status: String
    public let priority: Int
    public let attemptCount: Int
    public let lastErrorCode: String?
    public let lastErrorMessage: String?

    public init(record: AttachmentProcessingJobRecord) {
        self.jobKind = record.jobKind
        self.status = record.status
        self.priority = record.priority
        self.attemptCount = record.attemptCount
        self.lastErrorCode = record.lastErrorCode
        self.lastErrorMessage = record.lastErrorMessage
    }
}

public struct AttachmentSummaryKeyFieldViewData: Equatable, Sendable {
    public let label: String
    public let value: String
    public let evidenceChunkIds: [String]
}

public struct AttachmentSummaryFindingViewData: Equatable, Sendable {
    public let text: String
    public let evidenceChunkIds: [String]
}

public struct AttachmentSummaryViewData: Equatable, Sendable {
    public let summary: String
    public let keyFields: [AttachmentSummaryKeyFieldViewData]
    public let risks: [AttachmentSummaryFindingViewData]
    public let nextSteps: [AttachmentSummaryFindingViewData]
    public let evidenceChunkIds: [String]
    public let modelId: String
    public let promptVersion: String
    public let confidence: Double

    public init(output: AttachmentSummaryOutput) {
        self.summary = output.summary
        self.keyFields = output.keyFields.map {
            AttachmentSummaryKeyFieldViewData(
                label: $0.label,
                value: $0.value,
                evidenceChunkIds: $0.evidenceChunkIds
            )
        }
        self.risks = output.risks.map {
            AttachmentSummaryFindingViewData(
                text: $0.text,
                evidenceChunkIds: $0.evidenceChunkIds
            )
        }
        self.nextSteps = output.nextSteps.map {
            AttachmentSummaryFindingViewData(
                text: $0.text,
                evidenceChunkIds: $0.evidenceChunkIds
            )
        }
        self.evidenceChunkIds = output.evidenceChunkIds
        self.modelId = output.modelId
        self.promptVersion = output.promptVersion
        self.confidence = output.confidence
    }
}

public enum AttachmentSummaryDisplayState: Equatable, Sendable {
    case unavailable
    case available(AttachmentSummaryViewData)
    case failed(code: String, message: String)
}

public struct AttachmentInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let accountId: String
    public let messageId: String
    public let filename: String
    public let sizeBytes: Int?
    public let mime: String?
    public let localFileState: AttachmentLocalFileState
    public let extractionState: AttachmentExtractionDisplayState
    public let summaryState: AttachmentSummaryDisplayState
    public let processingState: AttachmentProcessingDisplayState?

    public init(record: AttachmentRecord) {
        self.init(record: record, extraction: nil, summaryArtifact: nil, processingJob: nil)
    }

    public init(id: String, filename: String, sizeBytes: Int?, mime: String?) {
        self.id = id
        self.accountId = ""
        self.messageId = ""
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.mime = mime
        self.localFileState = .waitingForLocalFile
        self.extractionState = .waitingForLocalFile
        self.summaryState = .unavailable
        self.processingState = nil
    }

    init(
        record: AttachmentRecord,
        extraction: AttachmentExtractionRecord?,
        summaryArtifact: AttachmentAIArtifactRecord?,
        processingJob: AttachmentProcessingJobRecord?
    ) {
        self.id = record.id
        self.accountId = record.accountId
        self.messageId = record.messageId
        self.filename = record.filename ?? "attachment"
        self.sizeBytes = record.sizeBytes
        self.mime = record.mime
        self.processingState = processingJob.map(AttachmentProcessingDisplayState.init)
        self.localFileState = Self.localFileState(
            record: record,
            extraction: extraction,
            summaryArtifact: summaryArtifact,
            processingJob: processingJob
        )
        self.extractionState = Self.extractionState(
            extraction: extraction,
            processingJob: processingJob
        )
        self.summaryState = Self.summaryState(from: summaryArtifact)
    }

    public var formattedSize: String {
        guard let bytes = sizeBytes else { return "" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    public var evidenceChunkIds: [String] {
        switch summaryState {
        case .available(let summary):
            return summary.evidenceChunkIds
        case .failed, .unavailable:
            return []
        }
    }

    public var isUnsupportedFormat: Bool {
        if case .unsupported = extractionState {
            return true
        }
        return false
    }

    private static func localFileState(
        record: AttachmentRecord,
        extraction: AttachmentExtractionRecord?,
        summaryArtifact: AttachmentAIArtifactRecord?,
        processingJob: AttachmentProcessingJobRecord?
    ) -> AttachmentLocalFileState {
        if processingJob?.isMissingLocalFileSignal == true {
            return .waitingForLocalFile
        }
        guard extraction != nil || summaryArtifact != nil || processingJob != nil else {
            return .waitingForLocalFile
        }
        return .available(
            byteCount: extraction?.byteCount ?? record.sizeBytes,
            contentHash: extraction?.contentHash
        )
    }

    private static func extractionState(
        extraction: AttachmentExtractionRecord?,
        processingJob: AttachmentProcessingJobRecord?
    ) -> AttachmentExtractionDisplayState {
        guard let extraction else {
            guard let processingJob else {
                return .waitingForLocalFile
            }
            if processingJob.isMissingLocalFileSignal {
                return .waitingForLocalFile
            }
            switch processingJob.status.normalizedAttachmentStatus {
            case "running", "processing", "started":
                return .running(status: processingJob.status)
            case "failed", "error":
                return .failed(code: processingJob.lastErrorCode, message: processingJob.lastErrorMessage)
            default:
                return .pending(status: processingJob.status)
            }
        }

        switch extraction.status.normalizedAttachmentStatus {
        case "succeeded", "success", "complete", "completed":
            return .succeeded(version: extraction.extractionVersion, contentHash: extraction.contentHash)
        case "unsupported", "unsupported_type", "unsupported_document_format":
            return .unsupported(code: extraction.errorCode, message: extraction.errorMessage)
        case "failed", "error":
            if extraction.isUnsupportedSignal {
                return .unsupported(code: extraction.errorCode, message: extraction.errorMessage)
            }
            return .failed(code: extraction.errorCode, message: extraction.errorMessage)
        case "running", "processing", "started":
            return .running(status: extraction.status)
        default:
            return .pending(status: extraction.status)
        }
    }

    private static func summaryState(from artifact: AttachmentAIArtifactRecord?) -> AttachmentSummaryDisplayState {
        guard let artifact else {
            return .unavailable
        }
        do {
            let data = Data(artifact.payloadJson.utf8)
            let output = try JSONDecoder().decode(AttachmentSummaryOutput.self, from: data)
            return .available(AttachmentSummaryViewData(output: output))
        } catch {
            return .failed(
                code: "artifact_decoding_failed",
                message: "Stored attachment summary artifact could not be decoded."
            )
        }
    }
}

private struct AttachmentStorageKey: Hashable {
    let accountId: String
    let messageId: String
    let attachmentId: String

    init(_ record: AttachmentRecord) {
        self.accountId = record.accountId
        self.messageId = record.messageId
        self.attachmentId = record.id
    }

    init(_ record: AttachmentExtractionRecord) {
        self.accountId = record.accountId
        self.messageId = record.messageId
        self.attachmentId = record.attachmentId
    }

    init(_ record: AttachmentAIArtifactRecord) {
        self.accountId = record.accountId
        self.messageId = record.messageId
        self.attachmentId = record.attachmentId
    }

    init(_ record: AttachmentProcessingJobRecord) {
        self.accountId = record.accountId
        self.messageId = record.messageId
        self.attachmentId = record.attachmentId
    }
}

private extension AttachmentExtractionRecord {
    var isUnsupportedSignal: Bool {
        [status, errorCode, errorMessage]
            .compactMap { $0?.normalizedAttachmentStatus }
            .contains { $0.contains("unsupported") }
    }
}

private extension AttachmentProcessingJobRecord {
    var isMissingLocalFileSignal: Bool {
        [status, lastErrorCode, lastErrorMessage]
            .compactMap { $0?.normalizedAttachmentStatus }
            .contains { value in
                value.contains("local_file_missing")
                    || value.contains("missing_local_file")
                    || value.contains("waiting_for_local_file")
                    || value.contains("missing_bytes")
            }
    }
}

private extension String {
    var normalizedAttachmentStatus: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

@Observable
@MainActor
public final class ThreadStore {
    public private(set) var messages: [MessageRow] = []
    public private(set) var subject: String = ""
    public private(set) var messageCount: Int = 0
    public private(set) var attachments: [AttachmentInfo] = []
    public private(set) var isStarred: Bool = false
    public var accountEmail: String = ""

    public var hasAttachment: Bool { !attachments.isEmpty }

    public var senderName: String {
        messages.first { $0.senderName != "?" }?.senderName ?? "?"
    }

    private let db: AppDatabase
    private var observationTask: Task<Void, Never>?

    public init(db: AppDatabase) {
        self.db = db
    }

    public func observe(threadId: String, accountId: String) {
        observationTask?.cancel()
        observationTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db in
                let thread = try ThreadRecord
                    .filter(Column("id") == threadId && Column("account_id") == accountId)
                    .fetchOne(db)

                let messages = try MessageRecord
                    .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                    .order(Column("sent_at").asc)
                    .fetchAll(db)

                let isStarred = try ThreadLabelRecord
                    .filter(Column("account_id") == accountId && Column("thread_id") == threadId && Column("label_id") == "STARRED")
                    .fetchOne(db) != nil

                let messageIds = messages.map(\.id)
                let attachments: [AttachmentRecord]
                let extractions: [AttachmentExtractionRecord]
                let artifacts: [AttachmentAIArtifactRecord]
                let processingJobs: [AttachmentProcessingJobRecord]
                if messageIds.isEmpty {
                    attachments = []
                    extractions = []
                    artifacts = []
                    processingJobs = []
                } else {
                    attachments = try AttachmentRecord
                        .filter(messageIds.contains(Column("message_id")) && Column("account_id") == accountId)
                        .fetchAll(db)
                    extractions = try AttachmentExtractionRecord
                        .filter(messageIds.contains(Column("message_id")) && Column("account_id") == accountId)
                        .fetchAll(db)
                    artifacts = try AttachmentAIArtifactRecord
                        .filter(
                            messageIds.contains(Column("message_id"))
                                && Column("account_id") == accountId
                                && Column("artifact_kind") == AttachmentAIArtifactCacheKey.summaryKind
                        )
                        .fetchAll(db)
                    processingJobs = try AttachmentProcessingJobRecord
                        .filter(messageIds.contains(Column("message_id")) && Column("account_id") == accountId)
                        .fetchAll(db)
                }

                return (thread, messages, attachments, extractions, artifacts, processingJobs, isStarred)
            }
            do {
                for try await (thread, records, attRecords, extractions, artifacts, processingJobs, starred) in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled, let self else { return }
                    let latestExtractions = Self.latestExtractionsByAttachment(extractions)
                    let latestArtifacts = Self.latestSummaryArtifactsByAttachment(artifacts)
                    let latestJobs = Self.latestProcessingJobsByAttachment(processingJobs)
                    let inlineByMessage = Dictionary(
                        grouping: attRecords.filter {
                            $0.contentId != nil && $0.dataBase64 != nil
                                && ($0.mime ?? "").hasPrefix("image/")
                        },
                        by: \.messageId
                    )
                    self.messages = records.map { rec in
                        let inlines = (inlineByMessage[rec.id] ?? []).compactMap { att -> InlineAttachment? in
                            guard let cid = att.contentId, let data = att.dataBase64 else { return nil }
                            return InlineAttachment(contentId: cid, mime: att.mime ?? "image/png", dataBase64: data)
                        }
                        return MessageRow(record: rec, inlineAttachments: inlines)
                    }
                    self.subject = thread?.subject ?? "(no subject)"
                    self.messageCount = thread?.messageCount ?? records.count
                    self.attachments = attRecords
                        .filter { $0.contentId == nil || $0.dataBase64 == nil }
                        .map { record in
                            let key = AttachmentStorageKey(record)
                            return AttachmentInfo(
                                record: record,
                                extraction: latestExtractions[key],
                                summaryArtifact: latestArtifacts[key],
                                processingJob: latestJobs[key]
                            )
                        }
                    self.isStarred = starred
                }
            } catch {
                // Observation ended
            }
        }
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        messages = []
        subject = ""
        messageCount = 0
        attachments = []
        isStarred = false
    }

    private static func latestExtractionsByAttachment(
        _ records: [AttachmentExtractionRecord]
    ) -> [AttachmentStorageKey: AttachmentExtractionRecord] {
        records.reduce(into: [:]) { result, record in
            let key = AttachmentStorageKey(record)
            guard let current = result[key] else {
                result[key] = record
                return
            }
            if record.extractionVersion > current.extractionVersion
                || record.extractionVersion == current.extractionVersion && record.updatedAt > current.updatedAt {
                result[key] = record
            }
        }
    }

    private static func latestSummaryArtifactsByAttachment(
        _ records: [AttachmentAIArtifactRecord]
    ) -> [AttachmentStorageKey: AttachmentAIArtifactRecord] {
        records.reduce(into: [:]) { result, record in
            let key = AttachmentStorageKey(record)
            guard let current = result[key] else {
                result[key] = record
                return
            }
            if record.extractionVersion > current.extractionVersion
                || record.extractionVersion == current.extractionVersion && record.updatedAt > current.updatedAt {
                result[key] = record
            }
        }
    }

    private static func latestProcessingJobsByAttachment(
        _ records: [AttachmentProcessingJobRecord]
    ) -> [AttachmentStorageKey: AttachmentProcessingJobRecord] {
        records.reduce(into: [:]) { result, record in
            let key = AttachmentStorageKey(record)
            guard let current = result[key] else {
                result[key] = record
                return
            }
            if record.updatedAt > current.updatedAt
                || record.updatedAt == current.updatedAt && record.priority > current.priority {
                result[key] = record
            }
        }
    }
}
