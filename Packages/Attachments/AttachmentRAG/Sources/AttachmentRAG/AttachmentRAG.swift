import AIKit
import AIPrompts
import AppFoundation
import AttachmentKit
import Foundation
import GRDB
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

public struct AttachmentSummaryEvidenceValidationError: Error, Sendable, Equatable {
    let kind: EvidenceValidationFailureKind
}

public actor AttachmentSummaryOrchestrator {
    let db: AppDatabase
    private let byteStore: AttachmentByteStore
    private let aiService: any AIService
    private let byteProvider: (any AttachmentByteProvider)?

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
        if let cached = try await fetchCachedSummary(request, fingerprint: blob.sha256) {
            do {
                try validateCachedSummary(cached, request: request)
                Self.logAttachmentEvent("attachment.summary_cache", status: "hit")
                return .summary(cached, cached: true)
            } catch let error as AttachmentSummaryEvidenceValidationError {
                Self.logEvidenceValidationFailure(error)
                try await deleteCachedSummary(request, fingerprint: blob.sha256)
            }
        }

        let (verifiedBlob, bytes) = try await loadVerifiedBlobBytes(blob, request: request)
        let extraction = AttachmentTextExtractor.extract(
            data: bytes,
            mime: request.mime,
            filename: request.filename
        )
        try await persistExtraction(
            extraction,
            request: request,
            fingerprint: verifiedBlob.sha256,
            byteCount: verifiedBlob.byteCount
        )

        guard extraction.status == .extracted else {
            let reason = extraction.unsupportedReason ?? "Unsupported attachment"
            Self.logAttachmentEvent(
                "attachment.summary_extraction",
                status: "unsupported",
                errorCategory: "unsupported_attachment"
            )
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
            Self.logEvidenceValidationFailure(error)
            throw error
        }

        try await persistSummary(
            summary,
            request: request,
            extractionVersion: extraction.extractionVersion,
            fingerprint: verifiedBlob.sha256
        )
        Self.logAttachmentEvent("attachment.summary_generation", status: "generated")
        return .summary(summary, cached: false)
    }

    private static func logEvidenceValidationFailure(_ error: AttachmentSummaryEvidenceValidationError) {
        logAttachmentEvent(
            "attachment.summary_evidence_validation",
            status: "failed",
            errorCategory: error.kind.rawValue,
            severity: .warning
        )
    }

    static func logAttachmentEvent(
        _ name: String,
        status: String,
        errorCategory: String? = nil,
        severity: PrivacyObservabilitySeverity = .info
    ) {
        var fields: [PrivacyObservabilityField: String] = [
            .status: status,
        ]
        if let errorCategory {
            fields[.errorCategory] = errorCategory
        }
        PrivacyObservability.log(
            PrivacyObservabilityEvent(category: .attachment, name: name, fields: fields),
            severity: severity
        )
    }

    private func loadOrFetchBlob(_ request: AttachmentSummaryRequest) async throws -> AttachmentBlobRecord {
        if let existing = try fetchBlob(request) {
            return existing
        }
        let (record, _) = try await fetchAndPersistBlob(request)
        return record
    }

    private func loadVerifiedBlobBytes(
        _ blob: AttachmentBlobRecord,
        request: AttachmentSummaryRequest
    ) async throws -> (AttachmentBlobRecord, Data) {
        do {
            let data = try byteStore.load(relativePath: blob.relativePath)
            guard data.count == blob.byteCount,
                  AttachmentByteStore.sha256Hex(data) == blob.sha256
            else {
                Self.logAttachmentEvent(
                    "attachment.blob_integrity",
                    status: "failed",
                    errorCategory: "hash_or_size_mismatch",
                    severity: .warning
                )
                try await removeStaleBlob(blob, request: request)
                return try await fetchAndPersistBlob(request)
            }
            return (blob, data)
        } catch {
            Self.logAttachmentEvent(
                "attachment.blob_load",
                status: "failed",
                errorCategory: "missing_or_invalid_path",
                severity: .warning
            )
            try await removeStaleBlob(blob, request: request)
            return try await fetchAndPersistBlob(request)
        }
    }

    private func fetchAndPersistBlob(_ request: AttachmentSummaryRequest) async throws -> (AttachmentBlobRecord, Data) {
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
        return (record, data)
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

    private func removeStaleBlob(_ blob: AttachmentBlobRecord, request: AttachmentSummaryRequest) async throws {
        try? byteStore.delete(relativePath: blob.relativePath)
        try await db.write { database in
            try database.execute(
                sql: """
                DELETE FROM attachment_blob
                WHERE account_id = ? AND message_id = ? AND attachment_id = ?
                """,
                arguments: [request.accountId, request.messageId, request.attachmentId]
            )
        }
    }
}
