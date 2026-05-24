import Testing
@testable import AIKit
import Foundation

@Suite("AIKit")
struct AIKitTests {
    @Test func moduleNameIsExported() {
        #expect(AIKit.moduleName == "AIKit")
    }

    @Test func threadInputMessageInit() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let msg = AIThreadInput.Message(from: "alice@example.com", sentAt: date, bodyText: "Hello")
        #expect(msg.from == "alice@example.com")
        #expect(msg.sentAt == date)
        #expect(msg.bodyText == "Hello")
    }

    @Test func threadInputAttachmentInit() {
        let att = AIThreadInput.Attachment(filename: "doc.pdf", mime: "application/pdf", pageCount: 3)
        #expect(att.filename == "doc.pdf")
        #expect(att.mime == "application/pdf")
        #expect(att.pageCount == 3)

        let attNoPages = AIThreadInput.Attachment(filename: "img.png", mime: "image/png")
        #expect(attNoPages.pageCount == nil)
    }

    @Test func threadBriefEquality() {
        let a = AIThreadBrief(summary: "Sum", confidence: 0.9)
        let b = AIThreadBrief(summary: "Sum", confidence: 0.9)
        #expect(a == b)

        let c = AIThreadBrief(summary: "Different", confidence: 0.9)
        #expect(a != c)
    }

    @Test func threadBriefOptionalFields() {
        let brief = AIThreadBrief(confidence: 0.5)
        #expect(brief.summary == nil)
        #expect(brief.request == nil)
        #expect(brief.deadline == nil)
        #expect(brief.risk == nil)
        #expect(brief.nextStep == nil)
        #expect(brief.evidence.isEmpty)
    }

    @Test func threadBriefFullFields() {
        let brief = AIThreadBrief(
            summary: "Contract renewal",
            request: "Sign by Friday",
            deadline: "2026-05-20",
            risk: "Late fee",
            nextStep: "Review clause 3",
            evidence: ["msg-1", "msg-2"],
            confidence: 0.95
        )
        #expect(brief.summary == "Contract renewal")
        #expect(brief.request == "Sign by Friday")
        #expect(brief.deadline == "2026-05-20")
        #expect(brief.risk == "Late fee")
        #expect(brief.nextStep == "Review clause 3")
        #expect(brief.evidence.count == 2)
        #expect(brief.confidence == 0.95)
    }

    @Test func mockAIServiceHappyPath() async throws {
        let expected = AIThreadBrief(summary: "Test", confidence: 0.8)
        let mock = MockAIService(stubbedBrief: expected)
        let input = AIThreadInput(messages: [
            .init(from: "bob@example.com", sentAt: .now, bodyText: "Hi"),
        ])

        let result = try await mock.threadBrief(input)
        #expect(result == expected)
        #expect(mock.threadBriefCallCount == 1)
    }

    @Test func mockAIServiceError() async {
        let mock = MockAIService(stubbedError: AIError.modelNotInstalled)
        let input = AIThreadInput(messages: [])

        do {
            _ = try await mock.threadBrief(input)
            Issue.record("Expected error")
        } catch {
            #expect(error is AIError)
        }
    }

    @Test func threadBriefServiceBuilderReturnsMockableService() async throws {
        // The live builder requires a real ModelManager + MLX. We verify the
        // MockAIService conforms to AIService and can be used as a drop-in,
        // which is the contract ThreadBriefService.live() also satisfies.
        let brief = AIThreadBrief(
            summary: "Builder test",
            request: "Approve budget",
            deadline: "Friday",
            confidence: 0.85
        )
        let service: any AIService = MockAIService(stubbedBrief: brief)
        let input = AIThreadInput(messages: [
            .init(from: "cfo@example.com", sentAt: .now, bodyText: "Please approve Q3 budget"),
        ])

        let result = try await service.threadBrief(input)
        #expect(result.summary == "Builder test")
        #expect(result.request == "Approve budget")
        #expect(result.deadline == "Friday")
        #expect(result.confidence == 0.85)
    }

    @Test func mockAIServiceInformationalThread() async throws {
        let brief = AIThreadBrief(
            summary: "Weekly digest",
            request: nil,
            deadline: nil,
            risk: nil,
            nextStep: nil,
            evidence: [],
            confidence: 0.4
        )
        let mock = MockAIService(stubbedBrief: brief)
        let input = AIThreadInput(messages: [
            .init(from: "digest@example.com", sentAt: .now, bodyText: "Here is your weekly summary"),
        ])

        let result = try await mock.threadBrief(input)
        #expect(result.request == nil)
        #expect(result.deadline == nil)
        #expect(result.risk == nil)
        #expect(result.confidence < 0.5)
    }

    // MARK: - draftReply Tests

    @Test func draftReplyHappyPath() async throws {
        let expectedReply = AIThreadReply(
            body: "Thanks, I'll review this by Friday.",
            evidenceMessageIDs: ["msg_1"],
            detectedReplyLanguage: "en",
            confidence: 0.85
        )
        let mock = MockAIService(stubbedReply: expectedReply)
        let input = AIThreadInput(messages: [
            .init(from: "boss@example.com", sentAt: .now, bodyText: "Please review the doc by Friday"),
        ])

        let result = try await mock.draftReply(input, tone: .concise, locale: .current, replyLanguage: "en")
        #expect(result == expectedReply)
        #expect(result.body == "Thanks, I'll review this by Friday.")
        #expect(result.detectedReplyLanguage == "en")
        #expect(mock.draftReplyCallCount == 1)
        #expect(mock.lastTone == .concise)
        #expect(mock.lastReplyLanguage == "en")
    }

    @Test func draftReplyPassesLanguage() async throws {
        let expectedReply = AIThreadReply(
            body: "Спасибо, посмотрю к пятнице.",
            evidenceMessageIDs: ["msg_1"],
            detectedReplyLanguage: "ru",
            confidence: 0.9
        )
        let mock = MockAIService(stubbedReply: expectedReply)
        let input = AIThreadInput(messages: [
            .init(from: "colleague@example.ru", sentAt: .now, bodyText: "Посмотри документ к пятнице"),
        ])

        let result = try await mock.draftReply(input, tone: .warm, locale: .current, replyLanguage: "ru")
        #expect(result.detectedReplyLanguage == "ru")
        #expect(mock.lastReplyLanguage == "ru")
        #expect(mock.lastTone == .warm)
    }

    @Test func draftReplyError() async {
        let mock = MockAIService(stubbedError: AIError.modelNotInstalled)
        let input = AIThreadInput(messages: [])

        do {
            _ = try await mock.draftReply(input, tone: .direct, locale: .current, replyLanguage: nil)
            Issue.record("Expected error")
        } catch {
            #expect(error is AIError)
        }
    }

    @Test func aiReplyToneAllCases() {
        #expect(AIReplyTone.allCases.count == 3)
        #expect(AIReplyTone.allCases.map(\.rawValue) == ["concise", "warm", "direct"])
    }

    @Test func aiThreadReplyEquality() {
        let a = AIThreadReply(body: "Hi", confidence: 0.8)
        let b = AIThreadReply(body: "Hi", confidence: 0.8)
        #expect(a == b)

        let c = AIThreadReply(body: "Different", confidence: 0.8)
        #expect(a != c)
    }

    @Test func attachmentSummaryHappyPath() async throws {
        let expected = AIAttachmentSummary(
            summary: "Invoice is due April 15.",
            keyFields: [AIKeyField(name: "Amount", value: "$4,250.00")],
            risks: [],
            nextSteps: ["Pay by April 15"],
            evidence: [AIAttachmentEvidence(chunkIndex: 0, quote: "due April 15")],
            confidence: 0.86
        )
        let mock = MockAIService(stubbedAttachmentSummary: expected)
        let input = AIAttachmentSummaryInput(
            filename: "invoice.txt",
            mime: "text/plain",
            chunks: [.init(index: 0, sourceOffset: 0, text: "Invoice is due April 15.")]
        )

        let result = try await mock.attachmentSummary(input)

        #expect(result == expected)
        #expect(mock.attachmentSummaryCallCount == 1)
        #expect(mock.lastAttachmentInput?.filename == "invoice.txt")
    }
}
