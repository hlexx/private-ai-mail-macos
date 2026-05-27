import AIKit
import AIPrompts
import AttachmentKit
import Foundation
import GRDB
import Persistence

extension AttachmentSummaryOrchestrator {
    private static let modernArtifactCacheColumns: Set<String> = [
        "task_id",
        "prompt_version",
        "schema_version",
        "input_fingerprint",
    ]

    func fetchCachedSummary(_ request: AttachmentSummaryRequest, fingerprint: String) throws -> AIAttachmentSummary? {
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

            if columns.isSuperset(of: Self.modernArtifactCacheColumns) {
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

    func validateCachedSummary(
        _ summary: AIAttachmentSummary,
        request: AttachmentSummaryRequest
    ) throws {
        let chunks = try fetchChunks(
            request,
            extractionVersion: AttachmentTextExtractor.extractionVersion
        )
        try Self.validateSummaryEvidence(summary, chunks: chunks)
    }

    private func fetchChunks(
        _ request: AttachmentSummaryRequest,
        extractionVersion: String
    ) throws -> [PromptAttachmentChunk] {
        try db.dbQueue.read { database in
            let columns = try Self.tableColumns("attachment_chunk", db: database)
            let textExpression: String
            if columns.contains("content_text"), columns.contains("text") {
                textExpression = "COALESCE(content_text, text)"
            } else if columns.contains("text") {
                textExpression = "text"
            } else {
                textExpression = "content_text"
            }

            let offsetExpression: String
            if columns.contains("source_offset") {
                offsetExpression = "source_offset"
            } else if columns.contains("source_start") {
                offsetExpression = "source_start"
            } else {
                offsetExpression = "0"
            }

            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT chunk_index, \(offsetExpression) AS source_offset, \(textExpression) AS chunk_text
                FROM attachment_chunk
                WHERE account_id = ?
                  AND message_id = ?
                  AND attachment_id = ?
                  AND extraction_version = ?
                ORDER BY chunk_index
                """,
                arguments: [
                    request.accountId,
                    request.messageId,
                    request.attachmentId,
                    extractionVersion,
                ]
            )

            return rows.compactMap { row in
                guard let index = row["chunk_index"] as Int?,
                      let text = row["chunk_text"] as String?
                else { return nil }
                let sourceOffset = row["source_offset"] as Int? ?? 0
                return PromptAttachmentChunk(index: index, sourceOffset: sourceOffset, text: text)
            }
        }
    }

    func deleteCachedSummary(_ request: AttachmentSummaryRequest, fingerprint: String) async throws {
        let metadata = AttachmentSummaryTask.metadata
        try await db.write { database in
            let columns = try Self.tableColumns("attachment_ai_artifact", db: database)
            if columns.isSuperset(of: Self.modernArtifactCacheColumns) {
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

private extension String {
    var sqlIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
