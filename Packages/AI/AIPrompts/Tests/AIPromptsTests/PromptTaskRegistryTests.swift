import Foundation
import Testing
@testable import AIPrompts

@Suite("PromptTaskRegistry")
struct PromptTaskRegistryTests {
    @Test func allRegisteredTasksHaveRunnableMetadata() {
        let metadata = PromptTaskRegistry.allMetadata

        #expect(metadata.map(\.id).sorted { $0.rawValue < $1.rawValue } == PromptTaskID.allCases.sorted { $0.rawValue < $1.rawValue })
        for item in metadata {
            #expect(!item.promptVersion.isEmpty)
            #expect(!item.schemaVersion.isEmpty)
            #expect(!item.modelProfile.isEmpty)
            #expect(item.maxInputCharacters > 0)
            #expect(item.maxOutputTokens > 0)
            #expect(!item.examples.isEmpty)
            #expect(!item.privacyCategory.isEmpty)
        }
    }

    @Test func promptTextBudgetTrimsLongText() {
        let text = String(repeating: "a", count: 32)
        let trimmed = PromptTextBudget.trimmed(text, maxCharacters: 12)

        #expect(trimmed.hasPrefix(String(repeating: "a", count: 12)))
        #expect(trimmed.contains("[trimmed 20 characters"))
    }

    @Test func attachmentSummaryParserAcceptsValidFixture() throws {
        let parsed = try AttachmentSummaryTask.parse(
            """
            {"summary":"Invoice due Friday","keyFields":[{"name":"amount","value":"USD 500"}],"risks":[],"nextSteps":["Pay Friday"],"evidence":[{"chunkIndex":0,"quote":"Amount: USD 500"}],"confidence":0.9}
            """
        )

        #expect(parsed.summary == "Invoice due Friday")
        #expect(parsed.keyFields.first?.name == "amount")
        #expect(parsed.evidence.first?.chunkIndex == 0)
    }

    @Test func attachmentSummaryParserAcceptsSeededDuplicateOpeningBrace() throws {
        let parsed = try AttachmentSummaryTask.parse(
            """
            {{"summary":"Invoice due Friday","keyFields":[],"risks":[],"nextSteps":[],"evidence":[{"chunkIndex":0,"quote":"Due Friday"}],"confidence":0.8}}
            """
        )

        #expect(parsed.summary == "Invoice due Friday")
        #expect(parsed.confidence == 0.8)
    }
}
