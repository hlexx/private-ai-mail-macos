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

    @Test func summarizeGeneratesAndThenUsesCache() async throws {
        let db = try makeAttachmentDatabase()
        let provider = FakeAttachmentByteProvider(data: Data("Amount due: EUR 1840".utf8))
        let ai = CountingAttachmentAIService()
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

    @Test func summarizeRejectsMissingEvidenceChunk() async throws {
        let db = try makeAttachmentDatabase()
        let ai = QueuedAttachmentAIService(outcomes: [
            .summary(makeSummary(evidence: [
                AIAttachmentEvidence(chunkIndex: 99, quote: "Amount due: EUR 1840"),
            ])),
        ])
        let orchestrator = try makeOrchestrator(db: db, aiService: ai)

        do {
            _ = try await orchestrator.summarize(defaultRequest())
            Issue.record("Expected missing chunk evidence to fail")
        } catch AttachmentRAGError.invalidAttachmentSummaryEvidence(let kind) {
            #expect(kind == "missingChunk")
        }

        #expect(try artifactCount(db) == 0)
        #expect(await ai.callCount == 1)
    }

    @Test func summarizeRejectsEmptyEvidenceForExtractedChunks() async throws {
        let db = try makeAttachmentDatabase()
        let ai = QueuedAttachmentAIService(outcomes: [
            .summary(makeSummary(evidence: [])),
        ])
        let orchestrator = try makeOrchestrator(db: db, aiService: ai)

        do {
            _ = try await orchestrator.summarize(defaultRequest())
            Issue.record("Expected empty evidence to fail")
        } catch AttachmentRAGError.invalidAttachmentSummaryEvidence(let kind) {
            #expect(kind == "missingEvidence")
        }

        #expect(try artifactCount(db) == 0)
        #expect(await ai.callCount == 1)
    }

    @Test func summarizeRejectsQuoteNotPresentInChunk() async throws {
        let db = try makeAttachmentDatabase()
        let ai = QueuedAttachmentAIService(outcomes: [
            .summary(makeSummary(evidence: [
                AIAttachmentEvidence(chunkIndex: 0, quote: "Different amount"),
            ])),
        ])
        let orchestrator = try makeOrchestrator(db: db, aiService: ai)

        do {
            _ = try await orchestrator.summarize(defaultRequest())
            Issue.record("Expected ungrounded quote evidence to fail")
        } catch AttachmentRAGError.invalidAttachmentSummaryEvidence(let kind) {
            #expect(kind == "quoteNotFound")
        }

        #expect(try artifactCount(db) == 0)
        #expect(await ai.callCount == 1)
    }

    @Test func malformedModelOutputDoesNotCreateSummaryArtifact() async throws {
        let db = try makeAttachmentDatabase()
        let ai = QueuedAttachmentAIService(outcomes: [
            .parseFailure(.invalidJSON("not-json")),
        ])
        let orchestrator = try makeOrchestrator(db: db, aiService: ai)

        await #expect(throws: AttachmentSummaryParser.ParseError.self) {
            try await orchestrator.summarize(defaultRequest())
        }

        #expect(try artifactCount(db) == 0)
        #expect(await ai.callCount == 1)
    }

    @Test func invalidEvidenceDoesNotPoisonCache() async throws {
        let db = try makeAttachmentDatabase()
        let ai = QueuedAttachmentAIService(outcomes: [
            .summary(makeSummary(evidence: [
                AIAttachmentEvidence(chunkIndex: 0, quote: "Not in chunk"),
            ])),
            .summary(makeSummary(evidence: [
                AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840"),
            ])),
        ])
        let orchestrator = try makeOrchestrator(db: db, aiService: ai)
        let request = defaultRequest()

        do {
            _ = try await orchestrator.summarize(request)
            Issue.record("Expected invalid evidence to fail")
        } catch AttachmentRAGError.invalidAttachmentSummaryEvidence(let kind) {
            #expect(kind == "quoteNotFound")
        }

        let retry = try await orchestrator.summarize(request)
        guard case .summary(let summary, let cached) = retry else {
            Issue.record("Expected retry to generate a summary")
            return
        }

        #expect(summary.summary == "Attachment summary")
        #expect(cached == false)
        #expect(try artifactCount(db) == 1)
        #expect(await ai.callCount == 2)
    }

    @Test func invalidCachedSummaryIsRevalidatedAndRegenerated() async throws {
        let db = try makeAttachmentDatabase()
        let data = Data("Amount due: EUR 1840".utf8)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let byteStore = AttachmentByteStore(baseURL: storeRoot)
        let stored = try byteStore.store(data, accountId: "a1", messageId: "m1", attachmentId: "att1")
        try seedCachedSummary(
            db,
            stored: stored,
            summary: makeSummary(evidence: [
                AIAttachmentEvidence(chunkIndex: 0, quote: "Not in chunk"),
            ]),
            chunkText: "Amount due: EUR 1840"
        )

        let ai = CountingAttachmentAIService()
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: byteStore,
            aiService: ai
        )
        let first = try await orchestrator.summarize(defaultRequest())
        let second = try await orchestrator.summarize(defaultRequest())

        guard case .summary(let firstSummary, let firstCached) = first,
              case .summary(_, let secondCached) = second else {
            Issue.record("Expected regenerated and then cached summaries")
            return
        }

        #expect(firstSummary.summary == "Attachment summary")
        #expect(firstCached == false)
        #expect(secondCached == true)
        #expect(await ai.callCount == 1)
        #expect(try artifactCount(db) == 1)
    }

    @Test func malformedCachedSummaryPayloadIsEvictedAndRegenerated() async throws {
        let db = try makeAttachmentDatabase()
        let data = Data("Amount due: EUR 1840".utf8)
        let fingerprint = AttachmentByteStore.sha256Hex(data)
        try seedCachedSummaryPayload(
            db,
            contentHash: fingerprint,
            payload: "{not-json"
        )

        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let provider = CountingAttachmentByteProvider(data: data)
        let ai = CountingAttachmentAIService()
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: provider
        )

        let first = try await orchestrator.summarize(defaultRequest())
        let second = try await orchestrator.summarize(defaultRequest())

        guard case .summary(let firstSummary, let firstCached) = first,
              case .summary(let secondSummary, let secondCached) = second else {
            Issue.record("Expected regenerated and cached summaries")
            return
        }

        #expect(firstSummary.summary == "Attachment summary")
        #expect(firstCached == false)
        #expect(secondSummary.summary == "Attachment summary")
        #expect(secondCached == true)
        #expect(await provider.callCount == 1)
        #expect(await ai.callCount == 1)
        #expect(try artifactCount(db) == 1)
    }

    @Test func emptyEvidenceCachedSummaryIsRevalidatedAndRegenerated() async throws {
        let db = try makeAttachmentDatabase()
        let data = Data("Amount due: EUR 1840".utf8)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let byteStore = AttachmentByteStore(baseURL: storeRoot)
        let stored = try byteStore.store(data, accountId: "a1", messageId: "m1", attachmentId: "att1")
        try seedCachedSummary(
            db,
            stored: stored,
            summary: makeSummary(evidence: []),
            chunkText: "Amount due: EUR 1840"
        )

        let ai = CountingAttachmentAIService()
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: byteStore,
            aiService: ai
        )

        let result = try await orchestrator.summarize(defaultRequest())

        guard case .summary(let summary, let cached) = result else {
            Issue.record("Expected regenerated summary")
            return
        }

        #expect(summary.evidence.count == 1)
        #expect(cached == false)
        #expect(await ai.callCount == 1)
        #expect(try artifactCount(db) == 1)
    }

    @Test func corruptStoredBlobIsRefetchedAndReplacedOnCacheMiss() async throws {
        let db = try makeAttachmentDatabase()
        let staleData = Data("Amount due: USD 1840".utf8)
        let freshData = Data("Amount due: EUR 1840".utf8)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let byteStore = AttachmentByteStore(baseURL: storeRoot)
        let stored = try byteStore.store(staleData, accountId: "a1", messageId: "m1", attachmentId: "att1")
        try seedBlobRecord(
            db,
            stored: stored,
            byteCount: freshData.count,
            sha256: AttachmentByteStore.sha256Hex(freshData)
        )

        let provider = CountingAttachmentByteProvider(data: freshData)
        let ai = CountingAttachmentAIService()
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: byteStore,
            aiService: ai,
            byteProvider: provider
        )

        let result = try await orchestrator.summarize(defaultRequest())

        guard case .summary(let summary, let cached) = result else {
            Issue.record("Expected regenerated summary")
            return
        }
        let record = try requireBlobRecord(db)
        let storedData = try byteStore.load(relativePath: record.relativePath)

        #expect(summary.summary == "Attachment summary")
        #expect(cached == false)
        #expect(await provider.callCount == 1)
        #expect(await ai.callCount == 1)
        #expect(record.byteCount == freshData.count)
        #expect(record.sha256 == AttachmentByteStore.sha256Hex(freshData))
        #expect(storedData == freshData)
    }

    @Test func corruptStoredBlobWithoutProviderThrowsUnavailable() async throws {
        let db = try makeAttachmentDatabase()
        let staleData = Data("Amount due: USD 1840".utf8)
        let freshData = Data("Amount due: EUR 1840".utf8)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let byteStore = AttachmentByteStore(baseURL: storeRoot)
        let stored = try byteStore.store(staleData, accountId: "a1", messageId: "m1", attachmentId: "att1")
        try seedBlobRecord(
            db,
            stored: stored,
            byteCount: freshData.count,
            sha256: AttachmentByteStore.sha256Hex(freshData)
        )

        let ai = CountingAttachmentAIService()
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: byteStore,
            aiService: ai
        )

        do {
            _ = try await orchestrator.summarize(defaultRequest())
            Issue.record("Expected unavailable bytes error")
        } catch AttachmentRAGError.attachmentBytesUnavailable {
        } catch {
            Issue.record("Expected unavailable bytes error, got \(error)")
        }

        #expect(await ai.callCount == 0)
        #expect(try blobCount(db) == 0)
    }

    @Test func validCachedSummaryReturnsWithoutLoadingAttachmentBytes() async throws {
        let db = try makeAttachmentDatabase()
        let data = Data("Amount due: EUR 1840".utf8)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let byteStore = AttachmentByteStore(baseURL: storeRoot)
        let stored = try byteStore.store(data, accountId: "a1", messageId: "m1", attachmentId: "att1")
        try seedCachedSummary(
            db,
            stored: stored,
            summary: makeSummary(evidence: [
                AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840"),
            ]),
            chunkText: "Amount due: EUR 1840"
        )
        try FileManager.default.removeItem(
            at: storeRoot.appendingPathComponent(stored.relativePath, isDirectory: false)
        )

        let ai = CountingAttachmentAIService()
        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: byteStore,
            aiService: ai
        )

        let result = try await orchestrator.summarize(defaultRequest())

        guard case .summary(let summary, let cached) = result else {
            Issue.record("Expected cached summary")
            return
        }
        #expect(summary.summary == "Attachment summary")
        #expect(cached == true)
        #expect(await ai.callCount == 0)
    }

    @Test func unsupportedAttachmentDoesNotCallAI() async throws {
        let db = try makeAttachmentDatabase(mime: "application/zip", filename: "archive.zip")
        let provider = FakeAttachmentByteProvider(data: Data([0x00, 0x01]))
        let ai = CountingAttachmentAIService()
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

private func seedCachedSummaryPayload(
    _ db: AppDatabase,
    contentHash: String,
    payload: String
) throws {
    let metadata = AttachmentSummaryTask.metadata
    try db.dbQueue.write { database in
        try AttachmentExtractionRecord(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: AttachmentTextExtractor.extractionVersion,
            status: AttachmentTextExtractionStatus.extracted.rawValue,
            contentHash: contentHash,
            mime: "text/plain",
            filename: "invoice.txt",
            byteCount: 20,
            createdAt: 1,
            updatedAt: 1,
            completedAt: 1,
            errorCode: nil,
            errorMessage: nil
        ).insert(database)
        try AttachmentAIArtifactRecord(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: AttachmentTextExtractor.extractionVersion,
            artifactKind: "\(metadata.id.rawValue):\(metadata.promptVersion):\(metadata.schemaVersion)",
            artifactVersion: 1,
            modelId: metadata.modelProfile,
            contentHash: contentHash,
            payloadJSON: payload,
            createdAt: 1,
            updatedAt: 1
        ).insert(database)
    }
}

private func makeOrchestrator(
    db: AppDatabase,
    aiService: any AIService,
    data: Data = Data("Amount due: EUR 1840".utf8)
) throws -> AttachmentSummaryOrchestrator {
    let storeRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return AttachmentSummaryOrchestrator(
        db: db,
        byteStore: .init(baseURL: storeRoot),
        aiService: aiService,
        byteProvider: FakeAttachmentByteProvider(data: data)
    )
}

private func defaultRequest() -> AttachmentSummaryRequest {
    AttachmentSummaryRequest(
        accountId: "a1",
        messageId: "m1",
        attachmentId: "att1",
        filename: "invoice.txt",
        mime: "text/plain"
    )
}

private func artifactCount(_ db: AppDatabase) throws -> Int {
    try db.dbQueue.read { database in
        try AttachmentAIArtifactRecord.fetchCount(database)
    }
}

private func blobCount(_ db: AppDatabase) throws -> Int {
    try db.dbQueue.read { database in
        try AttachmentBlobRecord.fetchCount(database)
    }
}

private func requireBlobRecord(_ db: AppDatabase) throws -> AttachmentBlobRecord {
    try db.dbQueue.read { database in
        let record = try AttachmentBlobRecord.fetchOne(database)
        return try #require(record)
    }
}

private func seedBlobRecord(
    _ db: AppDatabase,
    stored: AttachmentStoredBlob,
    byteCount: Int,
    sha256: String
) throws {
    try db.dbQueue.write { database in
        try AttachmentBlobRecord(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            relativePath: stored.relativePath,
            byteCount: byteCount,
            sha256: sha256,
            storedAt: 1
        ).insert(database)
    }
}

private func seedCachedSummary(
    _ db: AppDatabase,
    stored: AttachmentStoredBlob,
    summary: AIAttachmentSummary,
    chunkText: String
) throws {
    let payload = String(data: try JSONEncoder().encode(summary), encoding: .utf8) ?? "{}"
    let metadata = AttachmentSummaryTask.metadata
    try db.dbQueue.write { database in
        try AttachmentBlobRecord(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            relativePath: stored.relativePath,
            byteCount: stored.byteCount,
            sha256: stored.sha256,
            storedAt: 1
        ).insert(database)
        try AttachmentExtractionRecord(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: AttachmentTextExtractor.extractionVersion,
            status: AttachmentTextExtractionStatus.extracted.rawValue,
            contentHash: stored.sha256,
            mime: "text/plain",
            filename: "invoice.txt",
            byteCount: stored.byteCount,
            createdAt: 1,
            updatedAt: 1,
            completedAt: 1,
            errorCode: nil,
            errorMessage: nil
        ).insert(database)
        try AttachmentChunkRecord(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: AttachmentTextExtractor.extractionVersion,
            chunkIndex: 0,
            contentText: chunkText,
            sourceStart: 0,
            sourceEnd: chunkText.count,
            tokenCount: 0,
            createdAt: 1
        ).insert(database)
        try AttachmentAIArtifactRecord(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: AttachmentTextExtractor.extractionVersion,
            artifactKind: "\(metadata.id.rawValue):\(metadata.promptVersion):\(metadata.schemaVersion)",
            artifactVersion: 1,
            modelId: metadata.modelProfile,
            contentHash: stored.sha256,
            payloadJSON: payload,
            createdAt: 1,
            updatedAt: 1
        ).insert(database)
    }
}

private func makeSummary(evidence: [AIAttachmentEvidence]) -> AIAttachmentSummary {
    AIAttachmentSummary(
        summary: "Attachment summary",
        keyFields: [AIKeyField(name: "amount", value: "EUR 1840")],
        risks: [],
        nextSteps: ["Pay invoice"],
        evidence: evidence,
        confidence: 0.9
    )
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

private struct FakeAttachmentByteProvider: AttachmentByteProvider {
    let data: Data

    func fetchAttachmentData(accountId: String, messageId: String, attachmentId: String) async throws -> Data {
        data
    }
}

private actor CountingAttachmentByteProvider: AttachmentByteProvider {
    let data: Data
    private(set) var callCount = 0

    init(data: Data) {
        self.data = data
    }

    func fetchAttachmentData(accountId: String, messageId: String, attachmentId: String) async throws -> Data {
        callCount += 1
        return data
    }
}

private actor CountingAttachmentAIService: AIService {
    private(set) var callCount = 0

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
        return makeSummary(evidence: [
            AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840"),
        ])
    }
}

private actor QueuedAttachmentAIService: AIService {
    enum Outcome: Sendable {
        case summary(AIAttachmentSummary)
        case parseFailure(AttachmentSummaryParser.ParseError)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
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
        let outcome = outcomes.isEmpty
            ? .summary(makeSummary(evidence: [
                AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840"),
            ]))
            : outcomes.removeFirst()

        switch outcome {
        case .summary(let summary):
            return summary
        case .parseFailure(let error):
            throw error
        }
    }
}
