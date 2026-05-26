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
    private let db: AppDatabase
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
            Self.logger.info("Attachment summary cache hit for \(request.attachmentId, privacy: .public)")
            return .summary(cached, cached: true)
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

extension AttachmentSummaryOrchestrator {
    private func fetchCachedSummary(_ request: AttachmentSummaryRequest, fingerprint: String) throws -> AIAttachmentSummary? {
        let metadata = AttachmentSummaryTask.metadata
        let payload = try db.dbQueue.read { database -> String? in
            let columns = try Self.tableColumns("attachment_ai_artifact", db: database)
            let payloadExpression: String
            if columns.contains("payload_json"), columns.contains("content_json") {
                payloadExpression = "COALESCE(payload_json, content_json)"
            } else if columns.contains("content_json") {
                payloadExpression = "content_json"
            } else {
                payloadExpression = "payload_json"
            }

            if columns.contains("task_id"), columns.contains("input_fingerprint") {
                return try String.fetchOne(
                    database,
                    sql: """
                    SELECT \(payloadExpression) FROM attachment_ai_artifact
                    WHERE account_id = ?
                      AND message_id = ?
                      AND attachment_id = ?
                      AND task_id = ?
                      AND prompt_version = ?
                      AND schema_version = ?
                      AND model_id = ?
                      AND extraction_version = ?
                      AND input_fingerprint = ?
                    """,
                    arguments: [
                        request.accountId,
                        request.messageId,
                        request.attachmentId,
                        metadata.id.rawValue,
                        metadata.promptVersion,
                        metadata.schemaVersion,
                        metadata.modelProfile,
                        AttachmentTextExtractor.extractionVersion,
                        fingerprint,
                    ]
                )
            }

            return try String.fetchOne(
                database,
                sql: """
                SELECT \(payloadExpression) FROM attachment_ai_artifact
                WHERE account_id = ?
                  AND message_id = ?
                  AND attachment_id = ?
                  AND extraction_version = ?
                  AND artifact_kind = ?
                  AND artifact_version = ?
                  AND model_id = ?
                  AND content_hash = ?
                """,
                arguments: [
                    request.accountId,
                    request.messageId,
                    request.attachmentId,
                    AttachmentTextExtractor.extractionVersion,
                    Self.artifactKind(metadata),
                    1,
                    metadata.modelProfile,
                    fingerprint,
                ]
            )
        }
        guard let payload else { return nil }
        return try JSONDecoder().decode(AIAttachmentSummary.self, from: Data(payload.utf8))
    }

    private func persistExtraction(
        _ extraction: AttachmentTextExtractionResult,
        request: AttachmentSummaryRequest,
        fingerprint: String,
        byteCount: Int
    ) async throws {
        try await db.write { database in
            let columns = try Self.tableColumns("attachment_extraction", db: database)
            let now = Self.now()
            var values: [(String, DatabaseValueConvertible?)] = [
                ("account_id", request.accountId),
                ("message_id", request.messageId),
                ("attachment_id", request.attachmentId),
                ("extraction_version", extraction.extractionVersion),
                ("status", extraction.status.rawValue),
            ]
            Self.append(&values, "content_hash", fingerprint, ifPresentIn: columns)
            Self.append(&values, "mime", request.mime, ifPresentIn: columns)
            Self.append(&values, "filename", request.filename, ifPresentIn: columns)
            Self.append(&values, "byte_count", byteCount, ifPresentIn: columns)
            Self.append(&values, "created_at", now, ifPresentIn: columns)
            Self.append(&values, "updated_at", now, ifPresentIn: columns)
            Self.append(&values, "completed_at", now, ifPresentIn: columns)
            Self.append(&values, "error_code", extraction.status == .unsupported ? "unsupported" : nil, ifPresentIn: columns)
            Self.append(&values, "error_message", extraction.unsupportedReason, ifPresentIn: columns)
            Self.append(&values, "text", extraction.text, ifPresentIn: columns)
            Self.append(&values, "unsupported_reason", extraction.unsupportedReason, ifPresentIn: columns)
            Self.append(&values, "generated_at", now, ifPresentIn: columns)
            try Self.insertOrReplace(into: "attachment_extraction", values: values, db: database)
        }
    }

    private func persistChunks(
        _ chunks: [PromptAttachmentChunk],
        request: AttachmentSummaryRequest,
        extractionVersion: String
    ) async throws {
        try await db.write { database in
            try database.execute(
                sql: """
                DELETE FROM attachment_chunk
                WHERE account_id = ? AND message_id = ? AND attachment_id = ? AND extraction_version = ?
                """,
                arguments: [request.accountId, request.messageId, request.attachmentId, extractionVersion]
            )
            for chunk in chunks {
                let columns = try Self.tableColumns("attachment_chunk", db: database)
                var values: [(String, DatabaseValueConvertible?)] = [
                    ("account_id", request.accountId),
                    ("message_id", request.messageId),
                    ("attachment_id", request.attachmentId),
                    ("extraction_version", extractionVersion),
                    ("chunk_index", chunk.index),
                ]
                Self.append(&values, "content_text", chunk.text, ifPresentIn: columns)
                Self.append(&values, "text", chunk.text, ifPresentIn: columns)
                Self.append(&values, "source_offset", chunk.sourceOffset, ifPresentIn: columns)
                Self.append(&values, "source_start", chunk.sourceOffset, ifPresentIn: columns)
                Self.append(&values, "source_end", chunk.sourceOffset + chunk.text.count, ifPresentIn: columns)
                Self.append(&values, "token_count", 0, ifPresentIn: columns)
                Self.append(&values, "created_at", Self.now(), ifPresentIn: columns)
                try Self.insertOrReplace(into: "attachment_chunk", values: values, db: database)
            }
        }
    }

    private func persistSummary(
        _ summary: AIAttachmentSummary,
        request: AttachmentSummaryRequest,
        extractionVersion: String,
        fingerprint: String
    ) async throws {
        let metadata = AttachmentSummaryTask.metadata
        let data = try JSONEncoder().encode(summary)
        let payload = String(data: data, encoding: .utf8) ?? "{}"
        try await db.write { database in
            let columns = try Self.tableColumns("attachment_ai_artifact", db: database)
            let now = Self.now()
            var values: [(String, DatabaseValueConvertible?)] = [
                ("account_id", request.accountId),
                ("message_id", request.messageId),
                ("attachment_id", request.attachmentId),
                ("extraction_version", extractionVersion),
            ]
            Self.append(&values, "artifact_kind", Self.artifactKind(metadata), ifPresentIn: columns)
            Self.append(&values, "artifact_version", 1, ifPresentIn: columns)
            Self.append(&values, "model_id", metadata.modelProfile, ifPresentIn: columns)
            Self.append(&values, "content_hash", fingerprint, ifPresentIn: columns)
            Self.append(&values, "payload_json", payload, ifPresentIn: columns)
            Self.append(&values, "created_at", now, ifPresentIn: columns)
            Self.append(&values, "updated_at", now, ifPresentIn: columns)
            Self.append(&values, "task_id", metadata.id.rawValue, ifPresentIn: columns)
            Self.append(&values, "prompt_version", metadata.promptVersion, ifPresentIn: columns)
            Self.append(&values, "schema_version", metadata.schemaVersion, ifPresentIn: columns)
            Self.append(&values, "input_fingerprint", fingerprint, ifPresentIn: columns)
            Self.append(&values, "content_json", payload, ifPresentIn: columns)
            Self.append(&values, "generated_at", now, ifPresentIn: columns)
            try Self.insertOrReplace(into: "attachment_ai_artifact", values: values, db: database)
        }
    }

    private static func now() -> Int {
        Int(Date().timeIntervalSince1970)
    }

    private static func artifactKind(_ metadata: PromptTaskMetadata) -> String {
        "\(metadata.id.rawValue):\(metadata.promptVersion):\(metadata.schemaVersion)"
    }

    private static func tableColumns(_ table: String, db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table.sqlIdentifier))")
        return Set(rows.compactMap { $0["name"] as String? })
    }

    private static func append(
        _ values: inout [(String, DatabaseValueConvertible?)],
        _ column: String,
        _ value: DatabaseValueConvertible?,
        ifPresentIn columns: Set<String>
    ) {
        guard columns.contains(column) else { return }
        values.append((column, value))
    }

    private static func insertOrReplace(
        into table: String,
        values: [(String, DatabaseValueConvertible?)],
        db: Database
    ) throws {
        let columns = values.map { $0.0.sqlIdentifier }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        try db.execute(
            sql: "INSERT OR REPLACE INTO \(table.sqlIdentifier) (\(columns)) VALUES (\(placeholders))",
            arguments: StatementArguments(values.map { $0.1 })
        )
    }
}
