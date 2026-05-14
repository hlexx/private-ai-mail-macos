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
}
