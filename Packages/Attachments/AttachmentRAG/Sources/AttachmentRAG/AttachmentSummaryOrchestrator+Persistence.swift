import AIKit
import AIPrompts
import AppFoundation
import AttachmentKit
import Foundation
import GRDB
import Persistence

extension AttachmentSummaryOrchestrator {
    func persistExtraction(
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

    func persistChunks(
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

    func persistSummary(
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

    static func now() -> Int {
        Int(Date().timeIntervalSince1970)
    }

    static func artifactKind(_ metadata: PromptTaskMetadata) -> String {
        "\(metadata.id.rawValue):\(metadata.promptVersion):\(metadata.schemaVersion)"
    }

    static func validateSummary(
        _ summary: AIAttachmentSummary,
        chunks: [PromptAttachmentChunk]? = nil
    ) throws {
        guard !summary.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              summary.confidence >= 0,
              summary.confidence <= 1 else {
            throw AttachmentRAGError.summaryEvidenceMissing
        }

        if let chunks {
            if let failure = AttachmentEvidenceValidator.validate(summary.evidence, chunks: chunks) {
                throw AttachmentRAGError.invalidAttachmentSummaryEvidence(failure.rawValue)
            }
        } else if summary.evidence.isEmpty {
            throw AttachmentRAGError.summaryEvidenceMissing
        } else if summary.evidence.contains(where: { $0.chunkIndex < 0 || $0.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw AttachmentRAGError.summaryEvidenceMissing
        }
    }

    static func logSummary(
        status: String,
        request: AttachmentSummaryRequest,
        severity: PrivacyObservabilitySeverity = .info,
        errorCategory: String? = nil,
        sizeBucket: String? = nil
    ) {
        PrivacyObservability.log(
            Self.observabilityEvent(
                status: status,
                request: request,
                errorCategory: errorCategory,
                sizeBucket: sizeBucket
            ),
            severity: severity
        )
    }

    static func observabilityEvent(
        status: String,
        request: AttachmentSummaryRequest,
        errorCategory: String? = nil,
        sizeBucket: String? = nil
    ) -> PrivacyObservabilityEvent {
        var fields: [PrivacyObservabilityField: String] = [
            .accountID: request.accountId,
            .operation: "attachment_summary",
            .status: status,
            .attachmentCount: "1"
        ]
        if let errorCategory {
            fields[.errorCategory] = errorCategory
        }
        if let sizeBucket {
            fields[.sizeBucket] = sizeBucket
        }
        return PrivacyObservabilityEvent(category: .attachment, name: "attachment.summary", fields: fields)
    }

    static func sizeBucket(_ byteCount: Int) -> String {
        switch byteCount {
        case ..<16_384:
            return "lt_16kb"
        case ..<1_048_576:
            return "lt_1mb"
        case ..<10_485_760:
            return "lt_10mb"
        default:
            return "gte_10mb"
        }
    }
}
