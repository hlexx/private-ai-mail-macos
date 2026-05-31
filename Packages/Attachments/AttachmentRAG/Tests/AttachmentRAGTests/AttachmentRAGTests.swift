import Testing
import AIKit
import CoreGraphics
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
        #expect(firstSummary.evidence == [AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840")])
        #expect(secondSummary.summary == "Attachment summary")
        #expect(secondSummary.evidence == firstSummary.evidence)
        #expect(firstCached == false)
        #expect(secondCached == true)
        #expect(await ai.callCount == 1)
        #expect(try artifactCount(in: db) == 1)
    }

    @Test func summaryWithoutEvidenceIsRejectedAndNotPersisted() async throws {
        let db = try makeAttachmentDatabase()
        let provider = FakeAttachmentByteProvider(data: Data("Amount due: EUR 1840".utf8))
        let ai = CountingAttachmentAIService(summary: AIAttachmentSummary(
            summary: "Attachment summary",
            evidence: [],
            confidence: 0.8
        ))
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: provider
        )

        await #expect(throws: AttachmentRAGError.summaryEvidenceMissing) {
            try await orchestrator.summarize(
                AttachmentSummaryRequest(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    filename: "invoice.txt",
                    mime: "text/plain"
                )
            )
        }
        #expect(await ai.callCount == 1)
        #expect(try artifactCount(in: db) == 0)
    }

    @Test func summaryWithEvidenceOutsideExtractedChunksIsRejectedAndNotPersisted() async throws {
        let db = try makeAttachmentDatabase()
        let provider = FakeAttachmentByteProvider(data: Data("Amount due: EUR 1840".utf8))
        let ai = CountingAttachmentAIService(summary: AIAttachmentSummary(
            summary: "Attachment summary",
            evidence: [AIAttachmentEvidence(chunkIndex: 0, quote: "Invented quote")],
            confidence: 0.8
        ))
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot) }

        let orchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: .init(baseURL: storeRoot),
            aiService: ai,
            byteProvider: provider
        )

        await #expect(throws: AttachmentRAGError.summaryEvidenceMissing) {
            try await orchestrator.summarize(
                AttachmentSummaryRequest(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: "att1",
                    filename: "invoice.txt",
                    mime: "text/plain"
                )
            )
        }
        #expect(await ai.callCount == 1)
        #expect(try artifactCount(in: db) == 0)
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

    @Test func docxAttachmentReturnsUnsupportedWithoutEmptySummary() async throws {
        try await expectUnsupportedSummary(
            mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            filename: "contract.docx",
            data: Data([0x50, 0x4B, 0x03, 0x04]),
            reasonContains: "Unsupported"
        )
    }

    @Test func imageOCRAttachmentReturnsUnsupportedWithoutEmptySummary() async throws {
        try await expectUnsupportedSummary(
            mime: "image/png",
            filename: "scan.png",
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            reasonContains: "Unsupported"
        )
    }

    @Test func scannedPDFReturnsUnsupportedWithoutEmptySummary() async throws {
        try await expectUnsupportedSummary(
            mime: "application/pdf",
            filename: "scan.pdf",
            data: blankPDFData(),
            reasonContains: "extractable text"
        )
    }

    @Test func missingAttachmentIdFailsBeforeByteProvider() async throws {
        let db = try makeAttachmentDatabase()
        let provider = FakeAttachmentByteProvider(data: Data("raw private attachment text".utf8))
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

        await #expect(throws: AttachmentRAGError.missingAttachmentIdentifier) {
            try await orchestrator.summarize(
                AttachmentSummaryRequest(
                    accountId: "a1",
                    messageId: "m1",
                    attachmentId: " ",
                    filename: "invoice.txt",
                    mime: "text/plain"
                )
            )
        }
        #expect(await ai.callCount == 0)
    }

    @Test func privacyLogKeyDoesNotExposeRawAttachmentContentOrIdentifiers() {
        let request = AttachmentSummaryRequest(
            accountId: "acct-private",
            messageId: "message-private",
            attachmentId: "att-private",
            filename: "wire-instructions.txt",
            mime: "text/plain"
        )

        let key = AttachmentSummaryOrchestrator.privacyLogKey(for: request)

        #expect(key.hasPrefix("attachment:"))
        #expect(!key.contains(request.accountId))
        #expect(!key.contains(request.messageId))
        #expect(!key.contains(request.attachmentId))
        #expect(!key.contains("wire-instructions"))
        #expect(!key.contains("raw private attachment text"))
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

private func expectUnsupportedSummary(
    mime: String,
    filename: String,
    data: Data,
    reasonContains expectedReason: String
) async throws {
    let db = try makeAttachmentDatabase(mime: mime, filename: filename)
    let provider = FakeAttachmentByteProvider(data: data)
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
            filename: filename,
            mime: mime
        )
    )

    guard case .unsupported(let reason) = result else {
        Issue.record("Expected unsupported result")
        return
    }
    #expect(reason.contains(expectedReason))
    #expect(await ai.callCount == 0)
    #expect(try extractionStatus(in: db) == "unsupported")
    #expect(try artifactCount(in: db) == 0)
}

private func artifactCount(in db: AppDatabase) throws -> Int {
    try db.dbQueue.read { database in
        try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM attachment_ai_artifact") ?? 0
    }
}

private func extractionStatus(in db: AppDatabase) throws -> String? {
    try db.dbQueue.read { database in
        try String.fetchOne(database, sql: "SELECT status FROM attachment_extraction LIMIT 1")
    }
}

private func blankPDFData() -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 72, height: 72)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        preconditionFailure("Could not create test PDF")
    }
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

private struct FakeAttachmentByteProvider: AttachmentByteProvider {
    let data: Data

    func fetchAttachmentData(accountId: String, messageId: String, attachmentId: String) async throws -> Data {
        data
    }
}

private actor CountingAttachmentAIService: AIService {
    private(set) var callCount = 0
    private let summary: AIAttachmentSummary

    init(summary: AIAttachmentSummary = AIAttachmentSummary(
        summary: "Attachment summary",
        keyFields: [AIKeyField(name: "amount", value: "EUR 1840")],
        risks: [],
        nextSteps: ["Pay invoice"],
        evidence: [AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840")],
        confidence: 0.9
    )) {
        self.summary = summary
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
        return summary
    }
}
