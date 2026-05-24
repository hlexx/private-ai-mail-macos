import AIKit
import AIPrompts
import AttachmentKit
import Foundation
import GRDB
import Persistence
import os

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
        try await persistExtraction(extraction, request: request)

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

        try await persistSummary(
            summary,
            request: request,
            extractionVersion: extraction.extractionVersion,
            fingerprint: blob.sha256
        )
        Self.logger.info("Attachment summary generated for \(request.attachmentId, privacy: .public)")
        return .summary(summary, cached: false)
    }

    public static func chunk(_ text: String, maxCharacters: Int) -> [PromptAttachmentChunk] {
        guard !text.isEmpty else { return [] }
        var chunks: [PromptAttachmentChunk] = []
        var start = text.startIndex
        var offset = 0
        var index = 0

        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxCharacters, limitedBy: text.endIndex) ?? text.endIndex
            let chunkText = String(text[start..<end])
            chunks.append(PromptAttachmentChunk(index: index, sourceOffset: offset, text: chunkText))
            offset += chunkText.count
            index += 1
            start = end
        }

        return chunks
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

    private func fetchCachedSummary(_ request: AttachmentSummaryRequest, fingerprint: String) throws -> AIAttachmentSummary? {
        let metadata = AttachmentSummaryTask.metadata
        let record = try db.dbQueue.read { database in
            try AttachmentAIArtifactRecord.fetchOne(
                database,
                sql: """
                SELECT * FROM attachment_ai_artifact
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
        guard let record else { return nil }
        return try JSONDecoder().decode(AIAttachmentSummary.self, from: Data(record.contentJSON.utf8))
    }

    private func persistExtraction(_ extraction: AttachmentTextExtractionResult, request: AttachmentSummaryRequest) async throws {
        let record = AttachmentExtractionRecord(
            accountId: request.accountId,
            messageId: request.messageId,
            attachmentId: request.attachmentId,
            extractionVersion: extraction.extractionVersion,
            status: extraction.status.rawValue,
            mime: request.mime,
            text: extraction.text,
            unsupportedReason: extraction.unsupportedReason,
            generatedAt: Self.now()
        )
        try await db.write { database in
            try record.save(database)
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
                try AttachmentChunkRecord(
                    accountId: request.accountId,
                    messageId: request.messageId,
                    attachmentId: request.attachmentId,
                    extractionVersion: extractionVersion,
                    chunkIndex: chunk.index,
                    sourceOffset: chunk.sourceOffset,
                    text: chunk.text,
                    tokenCount: 0
                ).insert(database)
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
        let record = AttachmentAIArtifactRecord(
            accountId: request.accountId,
            messageId: request.messageId,
            attachmentId: request.attachmentId,
            taskId: metadata.id.rawValue,
            promptVersion: metadata.promptVersion,
            schemaVersion: metadata.schemaVersion,
            modelId: metadata.modelProfile,
            extractionVersion: extractionVersion,
            inputFingerprint: fingerprint,
            contentJSON: String(data: data, encoding: .utf8) ?? "{}",
            generatedAt: Self.now()
        )
        try await db.write { database in
            try record.save(database)
        }
    }

    private static func now() -> Int {
        Int(Date().timeIntervalSince1970)
    }
}
