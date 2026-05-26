import Testing
import AIKit
import AIPrompts
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

private func makeSummary(
    evidence: [AIAttachmentEvidence] = [AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840")]
) -> AIAttachmentSummary {
    AIAttachmentSummary(
        summary: "Attachment summary",
        keyFields: [AIKeyField(name: "amount", value: "EUR 1840")],
        risks: [],
        nextSteps: ["Pay invoice"],
        evidence: evidence,
        confidence: 0.9
    )
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
