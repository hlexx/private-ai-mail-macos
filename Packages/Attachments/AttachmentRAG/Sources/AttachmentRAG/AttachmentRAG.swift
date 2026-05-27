import AIKit
import AIPrompts
import AttachmentKit
import Foundation
import GRDB
import os
import Persistence

// MARK: - Public API

public enum AttachmentRAG {
    public static let moduleName = "AttachmentRAG"
}

public protocol AttachmentByteProvider: Sendable {
    func fetchAttachmentData(accountId: String, messageId: String, attachmentId: String) async throws -> Data
}

public struct AttachmentSummaryRequest: Sendable, Equatable {
    public let accountId: String
    public let messageId: String
    public let attachmentId: String
    public let filename: String
    public let mime: String

    public init(accountId: String, messageId: String, attachmentId: String, filename: String, mime: String) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.filename = filename
        self.mime = mime
    }
}

public enum AttachmentSummaryOrchestratorResult: Sendable, Equatable {
    case summary(AIAttachmentSummary, cached: Bool)
    case unsupported(String)
}

public enum AttachmentRAGError: Error, Sendable, Equatable {
    case attachmentBytesUnavailable
    case extractedTextMissing
}

enum EvidenceValidationFailureKind: String, Sendable, Equatable {
    case emptyQuote = "empty_quote"
    case missingChunk = "missing_chunk"
    case quoteNotFound = "quote_not_found"
}

struct AttachmentSummaryEvidenceValidationError: Error, Sendable, Equatable {
    let kind: EvidenceValidationFailureKind
}

public actor AttachmentSummaryOrchestrator {
    let db: AppDatabase
    private let byteStore: AttachmentByteStore
    private let aiService: any AIService
    private let byteProvider: (any AttachmentByteProvider)?

    private static let logger = Logger(
        subsystem: "com.privateaimail.attachments",
        category: "AttachmentRAG"
    )

    public init(
        db: AppDatabase,
        byteStore: AttachmentByteStore = AttachmentByteStore(baseURL: AttachmentByteStore.defaultBaseURL()),
        aiService: any AIService,
        byteProvider: (any AttachmentByteProvider)? = nil
    ) {
        self.db = db
        self.byteStore = byteStore
        self.aiService = aiService
        self.byteProvider = byteProvider
    }

    public func summarize(_ request: AttachmentSummaryRequest) async throws -> AttachmentSummaryOrchestratorResult {
        let blob = try await loadOrFetchBlob(request)
        if let cached = try fetchCachedSummary(request, fingerprint: blob.sha256) {
            do {
                try validateCachedSummary(cached, request: request)
                Self.logger.info("Attachment summary cache hit for \(request.attachmentId, privacy: .public)")
                return .summary(cached, cached: true)
            } catch let error as AttachmentSummaryEvidenceValidationError {
                Self.logEvidenceValidationFailure(error, request: request)
                try await deleteCachedSummary(request, fingerprint: blob.sha256)
            }
        }

        let bytes = try byteStore.load(relativePath: blob.relativePath)
        let extraction = AttachmentTextExtractor.extract(
            data: bytes,
            mime: request.mime,
            filename: request.filename
        )
        try await persistExtraction(extraction, request: request, fingerprint: blob.sha256, byteCount: blob.byteCount)

        guard extraction.status == .extracted else {
            let reason = extraction.unsupportedReason ?? "Unsupported attachment"
            Self.logger.info("Attachment summary unsupported for \(request.attachmentId, privacy: .public)")
            return .unsupported(reason)
        }

        guard let text = extraction.text, !text.isEmpty else {
            throw AttachmentRAGError.extractedTextMissing
        }

        let chunks = Self.chunk(text, maxCharacters: 4_000)
        try await persistChunks(chunks, request: request, extractionVersion: extraction.extractionVersion)

        let summary = try await aiService.attachmentSummary(
            AIAttachmentSummaryInput(
                filename: request.filename,
                mime: request.mime,
                chunks: chunks.map {
                    .init(index: $0.index, sourceOffset: $0.sourceOffset, text: $0.text)
                }
            )
        )

        do {
            try Self.validateSummaryEvidence(summary, chunks: chunks)
        } catch let error as AttachmentSummaryEvidenceValidationError {
            Self.logEvidenceValidationFailure(error, request: request)
            throw error
        }

        try await persistSummary(
            summary,
            request: request,
            extractionVersion: extraction.extractionVersion,
            fingerprint: blob.sha256
        )
        Self.logger.info("Attachment summary generated for \(request.attachmentId, privacy: .public)")
        return .summary(summary, cached: false)
    }

    private static func logEvidenceValidationFailure(
        _ error: AttachmentSummaryEvidenceValidationError,
        request: AttachmentSummaryRequest
    ) {
        let metadata = AttachmentSummaryTask.metadata
        logger.warning(
            "Attachment summary evidence validation failed attachment=\(request.attachmentId, privacy: .public) task=\(metadata.id.rawValue, privacy: .public) prompt=\(metadata.promptVersion, privacy: .public) kind=\(error.kind.rawValue, privacy: .public)"
        )
    }

    private func loadOrFetchBlob(_ request: AttachmentSummaryRequest) async throws -> AttachmentBlobRecord {
        if let existing = try fetchBlob(request) {
            return existing
        }
        guard let byteProvider else {
            throw AttachmentRAGError.attachmentBytesUnavailable
        }
        let data = try await byteProvider.fetchAttachmentData(
            accountId: request.accountId,
            messageId: request.messageId,
            attachmentId: request.attachmentId
        )
        let stored = try byteStore.store(
            data,
            accountId: request.accountId,
            messageId: request.messageId,
            attachmentId: request.attachmentId
        )
        let record = AttachmentBlobRecord(
            accountId: request.accountId,
            messageId: request.messageId,
            attachmentId: request.attachmentId,
            relativePath: stored.relativePath,
            byteCount: stored.byteCount,
            sha256: stored.sha256,
            storedAt: Self.now()
        )
        try await db.write { database in
            try record.save(database)
        }
        return record
    }

    private func fetchBlob(_ request: AttachmentSummaryRequest) throws -> AttachmentBlobRecord? {
        try db.dbQueue.read { database in
            try AttachmentBlobRecord.fetchOne(
                database,
                sql: """
                SELECT * FROM attachment_blob
                WHERE account_id = ? AND message_id = ? AND attachment_id = ?
                """,
                arguments: [request.accountId, request.messageId, request.attachmentId]
            )
        }
    }
}
