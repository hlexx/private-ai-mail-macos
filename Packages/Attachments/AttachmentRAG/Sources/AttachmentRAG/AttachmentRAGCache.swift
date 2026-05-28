import AIKit
import AIPrompts
import AttachmentKit
import Foundation
import GRDB

extension AttachmentSummaryOrchestrator {
    func fetchCachedSummary(_ request: AttachmentSummaryRequest, fingerprint: String) throws -> AIAttachmentSummary? {
        let cached = try db.dbQueue.read { database -> CachedSummary? in
            guard let payload = try Self.cachedSummaryPayload(request, fingerprint: fingerprint, db: database) else {
                return nil
            }
            let chunks = try Self.cachedChunks(request, db: database)
            return CachedSummary(payload: payload, chunks: chunks)
        }
        guard let cached else { return nil }

        let summary: AIAttachmentSummary
        do {
            summary = try JSONDecoder().decode(AIAttachmentSummary.self, from: Data(cached.payload.utf8))
        } catch {
            let metadata = AttachmentSummaryTask.metadata
            Self.logger.error(
                """
                Cached attachment summary decode failed \
                attachment_id=\(request.attachmentId, privacy: .public) \
                task_id=\(metadata.id.rawValue, privacy: .public) \
                prompt_version=\(metadata.promptVersion, privacy: .public) \
                schema_version=\(metadata.schemaVersion, privacy: .public) \
                failure_kind=\(Self.decodeFailureKind(error), privacy: .public)
                """
            )
            try deleteCachedSummary(request, fingerprint: fingerprint)
            return nil
        }
        if let failure = AttachmentEvidenceValidator.validate(summary.evidence, chunks: cached.chunks) {
            let metadata = AttachmentSummaryTask.metadata
            Self.logger.error(
                """
                Cached attachment summary evidence validation failed \
                attachment_id=\(request.attachmentId, privacy: .public) \
                task_id=\(metadata.id.rawValue, privacy: .public) \
                prompt_version=\(metadata.promptVersion, privacy: .public) \
                failure_kind=\(failure.rawValue, privacy: .public)
                """
            )
            try deleteCachedSummary(request, fingerprint: fingerprint)
            return nil
        }

        return summary
    }

    private static func decodeFailureKind(_ error: any Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(_):
            return "dataCorrupted"
        case DecodingError.keyNotFound(_, _):
            return "keyNotFound"
        case DecodingError.typeMismatch(_, _):
            return "typeMismatch"
        case DecodingError.valueNotFound(_, _):
            return "valueNotFound"
        default:
            return "decodeFailure"
        }
    }

    private struct CachedSummary {
        let payload: String
        let chunks: [PromptAttachmentChunk]
    }

    private static func cachedSummaryPayload(
        _ request: AttachmentSummaryRequest,
        fingerprint: String,
        db database: Database
    ) throws -> String? {
        let metadata = AttachmentSummaryTask.metadata
        let columns = try Self.tableColumns("attachment_ai_artifact", db: database)
        let payloadExpression = Self.payloadExpression(columns: columns)

        if columns.contains("task_id"), columns.contains("input_fingerprint") {
            let payload = try String.fetchOne(
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
            if let payload {
                return payload
            }
        }

        guard columns.contains("artifact_kind"), columns.contains("artifact_version") else {
            return nil
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

    private static func payloadExpression(columns: Set<String>) -> String {
        if columns.contains("payload_json"), columns.contains("content_json") {
            return "COALESCE(payload_json, content_json)"
        }
        if columns.contains("content_json") {
            return "content_json"
        }
        return "payload_json"
    }

    private static func cachedChunks(
        _ request: AttachmentSummaryRequest,
        db database: Database
    ) throws -> [PromptAttachmentChunk] {
        let columns = try Self.tableColumns("attachment_chunk", db: database)
        let textExpression: String
        if columns.contains("content_text"), columns.contains("text") {
            textExpression = "COALESCE(content_text, text)"
        } else if columns.contains("text") {
            textExpression = "text"
        } else {
            textExpression = "content_text"
        }

        let sourceOffsetExpression: String
        if columns.contains("source_offset"), columns.contains("source_start") {
            sourceOffsetExpression = "COALESCE(source_offset, source_start, 0)"
        } else if columns.contains("source_start") {
            sourceOffsetExpression = "COALESCE(source_start, 0)"
        } else if columns.contains("source_offset") {
            sourceOffsetExpression = "COALESCE(source_offset, 0)"
        } else {
            sourceOffsetExpression = "0"
        }

        return try Row.fetchAll(
            database,
            sql: """
            SELECT chunk_index,
                   \(sourceOffsetExpression) AS source_offset,
                   \(textExpression) AS content_text
            FROM attachment_chunk
            WHERE account_id = ?
              AND message_id = ?
              AND attachment_id = ?
              AND extraction_version = ?
            ORDER BY chunk_index ASC
            """,
            arguments: [
                request.accountId,
                request.messageId,
                request.attachmentId,
                AttachmentTextExtractor.extractionVersion,
            ]
        ).compactMap { row in
            guard let index = row["chunk_index"] as Int?,
                  let text = row["content_text"] as String? else {
                return nil
            }
            let sourceOffset = row["source_offset"] as Int? ?? 0
            return PromptAttachmentChunk(index: index, sourceOffset: sourceOffset, text: text)
        }
    }

    private func deleteCachedSummary(_ request: AttachmentSummaryRequest, fingerprint: String) throws {
        let metadata = AttachmentSummaryTask.metadata
        try db.dbQueue.write { database in
            let columns = try Self.tableColumns("attachment_ai_artifact", db: database)
            if columns.contains("task_id"), columns.contains("input_fingerprint") {
                try database.execute(
                    sql: """
                    DELETE FROM attachment_ai_artifact
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

            guard columns.contains("artifact_kind"), columns.contains("artifact_version") else {
                return
            }
            try database.execute(
                sql: """
                DELETE FROM attachment_ai_artifact
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
    }
}
