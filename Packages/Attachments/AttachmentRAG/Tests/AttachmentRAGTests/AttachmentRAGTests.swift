import Testing
import AIKit
import AIPrompts
import AttachmentKit
import Foundation
import GRDB
import Persistence
@testable import AttachmentRAG

@Suite("AttachmentRAG")
struct AttachmentRAGTests {
    @Test func moduleNameIsExported() {
        #expect(AttachmentRAG.moduleName == "AttachmentRAG")
    }

    @Test func chunkingIsDeterministic() {
        let chunks = AttachmentSummaryOrchestrator.chunk("abcdef", maxCharacters: 2)

        #expect(chunks.map(\.text) == ["ab", "cd", "ef"])
        #expect(chunks.map(\.sourceOffset) == [0, 2, 4])
        #expect(chunks.map(\.index) == [0, 1, 2])
    }

    @Test func evidenceValidatorAcceptsGroundedQuotesWithWhitespaceNormalization() throws {
        let summary = makeSummary(
            evidence: [
                AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840"),
                AIAttachmentEvidence(chunkIndex: 1, quote: "Due date: April 15"),
            ]
        )
        let chunks = [
            PromptAttachmentChunk(index: 0, sourceOffset: 0, text: "Amount due:\nEUR 1840"),
            PromptAttachmentChunk(index: 1, sourceOffset: 32, text: "Due date:\tApril   15"),
        ]

        try AttachmentSummaryOrchestrator.validateSummaryEvidence(summary, chunks: chunks)
    }

    @Test func missingEvidenceChunkFailsSummaryAndDoesNotPersistArtifact() async throws {
        let db = try makeAttachmentDatabase()
        let ai = SequencedAttachmentAIService(
            responses: [
                .summary(makeSummary(evidence: [AIAttachmentEvidence(chunkIndex: 7, quote: "Amount due: EUR 1840")])),
            ]
        )
        let (orchestrator, request, storeRoot) = makeOrchestrator(db: db, ai: ai)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        do {
            _ = try await orchestrator.summarize(request)
            Issue.record("Expected missing chunk validation failure")
        } catch let error as AttachmentSummaryEvidenceValidationError {
            #expect(error.kind == .missingChunk)
        }

        #expect(try attachmentArtifactCount(db) == 0)
        #expect(await ai.callCount == 1)
    }

    @Test func ungroundedEvidenceQuoteFailsSummaryAndDoesNotPersistArtifact() async throws {
        let db = try makeAttachmentDatabase()
        let ai = SequencedAttachmentAIService(
            responses: [
                .summary(makeSummary(evidence: [AIAttachmentEvidence(chunkIndex: 0, quote: "Total due: USD 999")])),
            ]
        )
        let (orchestrator, request, storeRoot) = makeOrchestrator(db: db, ai: ai)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        do {
            _ = try await orchestrator.summarize(request)
            Issue.record("Expected ungrounded quote validation failure")
        } catch let error as AttachmentSummaryEvidenceValidationError {
            #expect(error.kind == .quoteNotFound)
        }

        #expect(try attachmentArtifactCount(db) == 0)
        #expect(await ai.callCount == 1)
    }

    @Test func malformedModelOutputDoesNotPersistSummaryArtifact() async throws {
        let db = try makeAttachmentDatabase()
        let ai = SequencedAttachmentAIService(responses: [.invalidStructuredOutput("malformed attachment summary")])
        let (orchestrator, request, storeRoot) = makeOrchestrator(db: db, ai: ai)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        await #expect(throws: AIError.self) {
            _ = try await orchestrator.summarize(request)
        }
        #expect(try attachmentArtifactCount(db) == 0)
        #expect(await ai.callCount == 1)
    }

    @Test func validationFailureDoesNotPoisonSummaryCache() async throws {
        let db = try makeAttachmentDatabase()
        let ai = SequencedAttachmentAIService(
            responses: [
                .summary(makeSummary(evidence: [AIAttachmentEvidence(chunkIndex: 0, quote: "Not in the source chunk")])),
                .summary(makeSummary()),
            ]
        )
        let (orchestrator, request, storeRoot) = makeOrchestrator(db: db, ai: ai)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        await #expect(throws: AttachmentSummaryEvidenceValidationError.self) {
            _ = try await orchestrator.summarize(request)
        }
        #expect(try attachmentArtifactCount(db) == 0)

        let generated = try await orchestrator.summarize(request)
        guard case .summary(let generatedSummary, let generatedCached) = generated else {
            Issue.record("Expected valid generated summary after failed validation")
            return
        }
        #expect(generatedSummary.summary == "Attachment summary")
        #expect(generatedCached == false)
        #expect(try attachmentArtifactCount(db) == 1)

        let cached = try await orchestrator.summarize(request)
        guard case .summary(_, let cachedFlag) = cached else {
            Issue.record("Expected cached summary after valid generation")
            return
        }
        #expect(cachedFlag == true)
        #expect(await ai.callCount == 2)
    }

    @Test func summarizeGeneratesAndThenUsesCache() async throws {
        let db = try makeAttachmentDatabase()
        let provider = FakeAttachmentByteProvider(data: Data("Amount due: EUR 1840".utf8))
        let ai = SequencedAttachmentAIService()
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: provider
        )
        let request = AttachmentSummaryRequest(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            filename: "invoice.txt",
            mime: "text/plain"
        )

        let first = try await orchestrator.summarize(request)
        let second = try await orchestrator.summarize(request)

        guard case .summary(let firstSummary, let firstCached) = first,
              case .summary(let secondSummary, let secondCached) = second else {
            Issue.record("Expected generated and cached summaries")
            return
        }
        #expect(firstSummary.summary == "Attachment summary")
        #expect(secondSummary.summary == "Attachment summary")
        #expect(firstCached == false)
        #expect(secondCached == true)
        #expect(await ai.callCount == 1)
    }

    @Test func summarizeUsesExistingTextExtractionVersionCache() async throws {
        let db = try makeAttachmentDatabase()
        let summary = makeSummary()
        let payload = try String(decoding: JSONEncoder().encode(summary), as: UTF8.self)
        let fingerprint = "cached-sha"
        let metadata = AttachmentSummaryTask.metadata

        try await db.dbQueue.write { database in
            try database.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN task_id TEXT")
            try database.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN input_fingerprint TEXT")
            try AttachmentBlobRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                relativePath: "missing-cache-hit-file",
                byteCount: 24,
                sha256: fingerprint,
                storedAt: 1
            ).insert(database)
            try AttachmentExtractionRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: AttachmentTextExtractor.extractionVersion,
                status: "extracted",
                contentHash: fingerprint,
                mime: "text/plain",
                filename: "invoice.txt",
                byteCount: 24,
                createdAt: 2,
                updatedAt: 2,
                completedAt: 2,
                errorCode: nil,
                errorMessage: nil
            ).insert(database)
            try AttachmentChunkRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: AttachmentTextExtractor.extractionVersion,
                chunkIndex: 0,
                contentText: "Amount due: EUR 1840",
                sourceStart: 0,
                sourceEnd: 20,
                tokenCount: 4,
                createdAt: 2
            ).insert(database)
            try AttachmentAIArtifactRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: AttachmentTextExtractor.extractionVersion,
                artifactKind: "\(metadata.id.rawValue):\(metadata.promptVersion):\(metadata.schemaVersion)",
                artifactVersion: 1,
                modelId: metadata.modelProfile,
                contentHash: fingerprint,
                payloadJSON: payload,
                createdAt: 3,
                updatedAt: 3
            ).insert(database)
        }

        let ai = SequencedAttachmentAIService(responses: [.summary(makeSummary(summary: "should not be called"))])
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: FakeAttachmentByteProvider(data: Data("unused".utf8))
        )

        let result = try await orchestrator.summarize(makeRequest())

        guard case .summary(let cachedSummary, let cached) = result else {
            Issue.record("Expected preexisting cached summary")
            return
        }
        #expect(cached == true)
        #expect(cachedSummary.summary == "Attachment summary")
        #expect(await ai.callCount == 0)
    }

    @Test func invalidCachedEvidenceIsRegeneratedWithoutPoisoningCache() async throws {
        let db = try makeAttachmentDatabase()
        let invalidSummary = makeSummary(
            summary: "Invalid cached summary",
            evidence: [AIAttachmentEvidence(chunkIndex: 0, quote: "Not in the chunk")]
        )
        let payload = try String(decoding: JSONEncoder().encode(invalidSummary), as: UTF8.self)
        let fingerprint = "cached-sha"
        let metadata = AttachmentSummaryTask.metadata
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let relativePath = "a1/m1/att1.txt"
        let fileURL = storeRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("Amount due: EUR 1840".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        try await db.dbQueue.write { database in
            try AttachmentBlobRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                relativePath: relativePath,
                byteCount: 20,
                sha256: fingerprint,
                storedAt: 1
            ).insert(database)
            try AttachmentExtractionRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: AttachmentTextExtractor.extractionVersion,
                status: "extracted",
                contentHash: fingerprint,
                mime: "text/plain",
                filename: "invoice.txt",
                byteCount: 20,
                createdAt: 2,
                updatedAt: 2,
                completedAt: 2,
                errorCode: nil,
                errorMessage: nil
            ).insert(database)
            try AttachmentChunkRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: AttachmentTextExtractor.extractionVersion,
                chunkIndex: 0,
                contentText: "Amount due: EUR 1840",
                sourceStart: 0,
                sourceEnd: 20,
                tokenCount: 4,
                createdAt: 2
            ).insert(database)
            try AttachmentAIArtifactRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: AttachmentTextExtractor.extractionVersion,
                artifactKind: "\(metadata.id.rawValue):\(metadata.promptVersion):\(metadata.schemaVersion)",
                artifactVersion: 1,
                modelId: metadata.modelProfile,
                contentHash: fingerprint,
                payloadJSON: payload,
                createdAt: 3,
                updatedAt: 3
            ).insert(database)
        }

        let ai = SequencedAttachmentAIService(responses: [.summary(makeSummary())])
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: FakeAttachmentByteProvider(data: Data("unused".utf8))
        )

        let result = try await orchestrator.summarize(makeRequest())

        guard case .summary(let regenerated, let cached) = result else {
            Issue.record("Expected regenerated summary")
            return
        }
        #expect(regenerated.summary == "Attachment summary")
        #expect(cached == false)
        #expect(await ai.callCount == 1)
        #expect(try attachmentArtifactCount(db) == 1)
    }

    @Test func migratedLegacyIntegerExtractionVersionCacheIsReadable() async throws {
        let (db, dbRoot) = try makeMigratedLegacyAttachmentDatabase()
        defer { try? FileManager.default.removeItem(at: dbRoot) }
        let ai = SequencedAttachmentAIService(responses: [.summary(makeSummary(summary: "should not be called"))])
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: FakeAttachmentByteProvider(data: Data("unused".utf8))
        )

        let result = try await orchestrator.summarize(makeRequest())

        guard case .summary(let cachedSummary, let cached) = result else {
            Issue.record("Expected migrated cached summary")
            return
        }
        #expect(cached == true)
        #expect(cachedSummary.summary == "Attachment summary")
        #expect(await ai.callCount == 0)
    }

    @Test func unsupportedAttachmentDoesNotCallAI() async throws {
        let db = try makeAttachmentDatabase(mime: "application/zip", filename: "archive.zip")
        let provider = FakeAttachmentByteProvider(data: Data([0x00, 0x01]))
        let ai = SequencedAttachmentAIService()
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: provider
        )

        let result = try await orchestrator.summarize(
            AttachmentSummaryRequest(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                filename: "archive.zip",
                mime: "application/zip"
            )
        )

        guard case .unsupported(let reason) = result else {
            Issue.record("Expected unsupported result")
            return
        }
        #expect(reason.contains("Unsupported"))
        #expect(await ai.callCount == 0)
    }
}

private func makeAttachmentDatabase(
    mime: String = "text/plain",
    filename: String = "invoice.txt"
) throws -> AppDatabase {
    let db = try AppDatabase.openInMemorySync()
    try db.dbQueue.write { database in
        try AccountRecord(id: "a1", email: "a@example.com", createdAt: 1).insert(database)
        try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 1).insert(database)
        try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 1).insert(database)
        try AttachmentRecord(
            id: "att1",
            messageId: "m1",
            accountId: "a1",
            filename: filename,
            mime: mime,
            sizeBytes: 10
        ).insert(database)
    }
    return db
}

private func makeRequest() -> AttachmentSummaryRequest {
    AttachmentSummaryRequest(
        accountId: "a1",
        messageId: "m1",
        attachmentId: "att1",
        filename: "invoice.txt",
        mime: "text/plain"
    )
}

private func makeOrchestrator(
    db: AppDatabase,
    ai: any AIService,
    data: Data = Data("Amount due: EUR 1840".utf8)
) -> (AttachmentSummaryOrchestrator, AttachmentSummaryRequest, URL) {
    let storeRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let orchestrator = AttachmentSummaryOrchestrator(
        db: db,
        byteStore: .init(baseURL: storeRoot),
        aiService: ai,
        byteProvider: FakeAttachmentByteProvider(data: data)
    )
    return (orchestrator, makeRequest(), storeRoot)
}

private func attachmentArtifactCount(_ db: AppDatabase) throws -> Int {
    try db.dbQueue.read { database in
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM attachment_ai_artifact") ?? 0
    }
}

private func makeMigratedLegacyAttachmentDatabase() throws -> (AppDatabase, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let dbURL = root.appendingPathComponent("legacy.sqlite")
    let dbQueue = try DatabaseQueue(path: dbURL.path)

    let summary = makeSummary()
    let payload = try String(decoding: JSONEncoder().encode(summary), as: UTF8.self)
    let fingerprint = "legacy-fingerprint"
    let metadata = AttachmentSummaryTask.metadata

    try dbQueue.write { database in
        try createLegacyBaseSchemaForRAG(database)
        try LegacyIntegerAttachmentDataPlaneForRAG.migrate(database)
        try addLegacyCompatibilityColumnsForRAG(database)
        try AccountRecord(id: "a1", email: "a@example.com", createdAt: 1).insert(database)
        try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 1).insert(database)
        try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 1).insert(database)
        try AttachmentRecord(id: "att1", messageId: "m1", accountId: "a1").insert(database)

        try database.execute(
            sql: """
            INSERT INTO attachment_extraction (
                account_id, message_id, attachment_id, extraction_version, status,
                content_hash, mime, filename, byte_count, created_at, updated_at,
                completed_at, text, generated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                "a1", "m1", "att1", AttachmentTextExtractor.extractionVersion, "extracted",
                fingerprint, "text/plain", "invoice.txt", 20, 2, 2, 2,
                "Amount due: EUR 1840", 2,
            ]
        )
        try database.execute(
            sql: """
            INSERT INTO attachment_chunk (
                account_id, message_id, attachment_id, extraction_version, chunk_index,
                content_text, source_start, source_end, token_count, created_at, text, source_offset
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                "a1", "m1", "att1", AttachmentTextExtractor.extractionVersion, 0,
                "Amount due: EUR 1840", 0, 20, 4, 2, "Amount due: EUR 1840", 0,
            ]
        )
        try database.execute(
            sql: """
            INSERT INTO attachment_ai_artifact (
                account_id, message_id, attachment_id, extraction_version, artifact_kind,
                artifact_version, model_id, content_hash, payload_json, created_at,
                updated_at, content_json, task_id, prompt_version, schema_version,
                input_fingerprint, generated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                "a1", "m1", "att1", AttachmentTextExtractor.extractionVersion,
                "\(metadata.id.rawValue):\(metadata.promptVersion):\(metadata.schemaVersion)",
                1, metadata.modelProfile, fingerprint, payload, 3, 3, payload,
                metadata.id.rawValue, metadata.promptVersion, metadata.schemaVersion,
                fingerprint, 3,
            ]
        )
        try AttachmentBlobRecord(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            relativePath: "missing-cache-hit-file",
            byteCount: 20,
            sha256: fingerprint,
            storedAt: 4
        ).insert(database)
    }

    return (try AppDatabase.openSync(at: dbURL.path), root)
}

private func makeSummary(
    summary: String = "Attachment summary",
    evidence: [AIAttachmentEvidence] = [AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840")]
) -> AIAttachmentSummary {
    AIAttachmentSummary(
        summary: summary,
        keyFields: [AIKeyField(name: "amount", value: "EUR 1840")],
        risks: [],
        nextSteps: ["Pay invoice"],
        evidence: evidence,
        confidence: 0.9
    )
}

private enum LegacyIntegerAttachmentDataPlaneForRAG {
    static func migrate(_ db: Database) throws {
        try db.create(table: "attachment_extraction") { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .integer).notNull()
            t.column("status", .text).notNull()
            t.column("content_hash", .text)
            t.column("mime", .text)
            t.column("filename", .text)
            t.column("byte_count", .integer)
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.column("completed_at", .integer)
            t.column("error_code", .text)
            t.column("error_message", .text)
            t.primaryKey(["account_id", "message_id", "attachment_id", "extraction_version"])
            t.foreignKey(
                ["account_id", "message_id", "attachment_id"],
                references: "attachment",
                columns: ["account_id", "message_id", "id"],
                onDelete: .cascade
            )
        }
        try db.create(table: "attachment_chunk") { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .integer).notNull()
            t.column("chunk_index", .integer).notNull()
            t.column("content_text", .text).notNull()
            t.column("source_reference", .text)
            t.column("page_number", .integer)
            t.column("source_start", .integer)
            t.column("source_end", .integer)
            t.column("token_count", .integer)
            t.column("created_at", .integer).notNull()
            t.primaryKey(["account_id", "message_id", "attachment_id", "extraction_version", "chunk_index"])
            t.foreignKey(
                ["account_id", "message_id", "attachment_id", "extraction_version"],
                references: "attachment_extraction",
                columns: ["account_id", "message_id", "attachment_id", "extraction_version"],
                onDelete: .cascade
            )
        }
        try db.create(table: "attachment_ai_artifact") { t in
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("extraction_version", .integer).notNull()
            t.column("artifact_kind", .text).notNull()
            t.column("artifact_version", .integer).notNull()
            t.column("model_id", .text)
            t.column("content_hash", .text)
            t.column("payload_json", .text).notNull()
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.primaryKey([
                "account_id", "message_id", "attachment_id",
                "extraction_version", "artifact_kind", "artifact_version",
            ])
            t.foreignKey(
                ["account_id", "message_id", "attachment_id", "extraction_version"],
                references: "attachment_extraction",
                columns: ["account_id", "message_id", "attachment_id", "extraction_version"],
                onDelete: .cascade
            )
        }
        try db.create(table: "attachment_processing_job") { t in
            t.primaryKey("id", .text)
            t.column("account_id", .text).notNull()
            t.column("message_id", .text).notNull()
            t.column("attachment_id", .text).notNull()
            t.column("job_kind", .text).notNull()
            t.column("status", .text).notNull()
            t.column("priority", .integer).notNull().defaults(to: 0)
            t.column("attempt_count", .integer).notNull().defaults(to: 0)
            t.column("available_at", .integer).notNull()
            t.column("created_at", .integer).notNull()
            t.column("updated_at", .integer).notNull()
            t.column("last_error_code", .text)
            t.column("last_error_message", .text)
            t.foreignKey(
                ["account_id", "message_id", "attachment_id"],
                references: "attachment",
                columns: ["account_id", "message_id", "id"],
                onDelete: .cascade
            )
        }
    }
}

private func createLegacyBaseSchemaForRAG(_ db: Database) throws {
    try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
    for identifier in [
        "M001_InitialSchema",
        "M002_Labels",
        "M003_TrustedSender",
        "M004_TranslatedText",
        "M005_ThreadLabelAccountId",
        "M006_ThreadBrief",
        "M007_AttachmentCID",
        "M008_BackfillInboxLabel",
        "M009_BackfillInboxLabelV2",
        "M010_SignalLabelReconcile",
        "M011_AttachmentDataPlane",
        "M012_AttachmentBlobStore",
        "M013_ThreadBriefCacheIdentity",
    ] {
        try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [identifier])
    }

    try db.execute(sql: """
        CREATE TABLE account (
            id TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            email TEXT NOT NULL,
            display_name TEXT,
            created_at INTEGER NOT NULL,
            last_synced_at INTEGER
        )
        """)
    try db.execute(sql: """
        CREATE TABLE thread (
            id TEXT NOT NULL,
            account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
            subject TEXT,
            snippet TEXT,
            last_message_at INTEGER NOT NULL,
            message_count INTEGER NOT NULL DEFAULT 0,
            has_unread INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (account_id, id)
        )
        """)
    try db.execute(sql: """
        CREATE TABLE message (
            id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
            message_id_header TEXT,
            from_addr TEXT,
            to_addr TEXT,
            cc_addr TEXT,
            sent_at INTEGER NOT NULL,
            snippet TEXT,
            body_html TEXT,
            body_text TEXT,
            translated_text TEXT,
            flags INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (account_id, id)
        )
        """)
    try db.execute(sql: """
        CREATE TABLE attachment (
            id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
            filename TEXT,
            mime TEXT,
            size_bytes INTEGER,
            content_id TEXT,
            data_base64 TEXT,
            PRIMARY KEY (account_id, message_id, id),
            FOREIGN KEY (account_id, message_id) REFERENCES message(account_id, id) ON DELETE CASCADE
        )
        """)
    try db.execute(sql: """
        CREATE TABLE attachment_blob (
            account_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            attachment_id TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            byte_count INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            stored_at INTEGER NOT NULL,
            PRIMARY KEY (account_id, message_id, attachment_id),
            FOREIGN KEY (account_id, message_id, attachment_id)
            REFERENCES attachment(account_id, message_id, id) ON DELETE CASCADE
        )
        """)
}

private func addLegacyCompatibilityColumnsForRAG(_ db: Database) throws {
    try db.execute(sql: "ALTER TABLE attachment_extraction ADD COLUMN text TEXT")
    try db.execute(sql: "ALTER TABLE attachment_extraction ADD COLUMN generated_at INTEGER")
    try db.execute(sql: "ALTER TABLE attachment_chunk ADD COLUMN text TEXT")
    try db.execute(sql: "ALTER TABLE attachment_chunk ADD COLUMN source_offset INTEGER")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN content_json TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN task_id TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN prompt_version TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN schema_version TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN input_fingerprint TEXT")
    try db.execute(sql: "ALTER TABLE attachment_ai_artifact ADD COLUMN generated_at INTEGER")
}

private struct FakeAttachmentByteProvider: AttachmentByteProvider {
    let data: Data

    func fetchAttachmentData(accountId: String, messageId: String, attachmentId: String) async throws -> Data {
        data
    }
}

private actor SequencedAttachmentAIService: AIService {
    enum Response: Sendable {
        case summary(AIAttachmentSummary)
        case invalidStructuredOutput(String)
    }

    private var responses: [Response]
    private(set) var callCount = 0

    init(responses: [Response] = [.summary(makeSummary())]) {
        self.responses = responses
    }

    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        AIThreadBrief(summary: "unused", confidence: 0.1)
    }

    func draftReply(
        _ input: AIThreadInput,
        tone: AIReplyTone,
        locale: Locale,
        replyLanguage: String?
    ) async throws -> AIThreadReply {
        AIThreadReply(body: "unused")
    }

    func attachmentSummary(_ input: AIAttachmentSummaryInput) async throws -> AIAttachmentSummary {
        callCount += 1
        let response = responses.isEmpty ? .summary(makeSummary()) : responses.removeFirst()
        switch response {
        case .summary(let summary):
            return summary
        case .invalidStructuredOutput(let diagnostic):
            throw AIError.invalidStructuredOutput(diagnostic)
        }
    }
}
