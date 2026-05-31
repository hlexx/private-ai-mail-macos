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
    case missingAttachmentIdentifier
    case attachmentBytesUnavailable
    case extractedTextMissing
    case summaryEvidenceMissing
    case invalidAttachmentSummaryEvidence(String)
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
        if let cached = try fetchCachedSummary(request, fingerprint: blob.sha256) {
            Self.logSummary(status: "cache_hit", request: request, sizeBucket: Self.sizeBucket(blob.byteCount))
            return .summary(cached, cached: true)
        }

        let verifiedBlob = try await loadVerifiedBlobBytes(blob, request: request)
        let extraction = AttachmentTextExtractor.extract(
            data: verifiedBlob.data,
            mime: request.mime,
            filename: request.filename
        )
        try await persistExtraction(
            extraction,
            request: request,
            fingerprint: verifiedBlob.record.sha256,
            byteCount: verifiedBlob.record.byteCount
        )

        guard extraction.status == .extracted else {
            let reason = extraction.unsupportedReason ?? "Unsupported attachment"
            Self.logSummary(
                status: "unsupported",
                request: request,
                errorCategory: "unsupported_operation",
                sizeBucket: Self.sizeBucket(blob.byteCount)
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
            try Self.validateSummary(summary, chunks: chunks)
        } catch AttachmentRAGError.invalidAttachmentSummaryEvidence(let failureKind) {
            Self.logSummary(
                status: "failed",
                request: request,
                severity: .error,
                errorCategory: failureKind,
                sizeBucket: Self.sizeBucket(blob.byteCount)
            )
            throw AttachmentRAGError.invalidAttachmentSummaryEvidence(failureKind)
        }

        try await persistSummary(
            summary,
            request: request,
            extractionVersion: extraction.extractionVersion,
            fingerprint: verifiedBlob.record.sha256
        )
        Self.logSummary(status: "generated", request: request, sizeBucket: Self.sizeBucket(blob.byteCount))
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
        guard !request.attachmentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AttachmentRAGError.missingAttachmentIdentifier
        }
        if let existing = try fetchBlob(request) {
            return existing
        }
        return try await fetchAndStoreBlob(request)
    }

    private func loadVerifiedBlobBytes(
        _ blob: AttachmentBlobRecord,
        request: AttachmentSummaryRequest
    ) async throws -> VerifiedAttachmentBlob {
        let failureKind: String?
        do {
            let data = try byteStore.load(relativePath: blob.relativePath)
            if data.count != blob.byteCount {
                failureKind = "byteCountMismatch"
            } else if AttachmentByteStore.sha256Hex(data) != blob.sha256 {
                failureKind = "sha256Mismatch"
            } else {
                return VerifiedAttachmentBlob(record: blob, data: data)
            }
        } catch {
            failureKind = blobFileExists(blob.relativePath) ? "loadFailed" : "missingFile"
        }

        Self.logSummary(
            status: "cache_invalidated",
            request: request,
            severity: .error,
            errorCategory: failureKind ?? "unknown"
        )
        try await removeStaleBlob(blob, request: request)
        let freshBlob = try await fetchAndStoreBlob(request)
        let freshData = try byteStore.load(relativePath: freshBlob.relativePath)
        return VerifiedAttachmentBlob(record: freshBlob, data: freshData)
    }

    private func fetchAndStoreBlob(_ request: AttachmentSummaryRequest) async throws -> AttachmentBlobRecord {
        guard let byteProvider else {
            throw AttachmentRAGError.attachmentBytesUnavailable
        }
        let data: Data
        do {
            data = try await byteProvider.fetchAttachmentData(
                accountId: request.accountId,
                messageId: request.messageId,
                attachmentId: request.attachmentId
            )
        } catch {
            Self.logSummary(
                status: "failed",
                request: request,
                severity: .error,
                errorCategory: "attachment_bytes_unavailable"
            )
            throw error
        }
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

    private func blobFileExists(_ relativePath: String) -> Bool {
        (try? byteStore.fileExists(relativePath: relativePath)) == true
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

private struct VerifiedAttachmentBlob: Sendable {
    let record: AttachmentBlobRecord
    let data: Data
}
