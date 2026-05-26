import Foundation
import Testing
@testable import AIPrompts

@Suite("ThreadBriefPrompt")
struct ThreadBriefPromptTests {

    @Test("system prompt is non-empty and concise")
    func systemPromptBasics() {
        let prompt = ThreadBriefPrompt.systemPrompt
        #expect(!prompt.isEmpty)
        #expect(prompt.contains("JSON"))
        #expect(prompt.contains("null"))
        #expect(prompt.contains("confidence"))
        #expect(!prompt.contains("Q3 goals"))
        #expect(!prompt.contains("Example output"))
    }

    @Test("task prompt renders messages and attachments")
    func taskPromptRendering() {
        let messages = [
            PromptMessage(
                from: "Alice",
                sentAt: Date(timeIntervalSince1970: 1_700_000_000),
                bodyText: "Please review the attached proposal."
            ),
            PromptMessage(
                from: "Bob",
                sentAt: Date(timeIntervalSince1970: 1_700_003_600),
                bodyText: "Looks good, approved."
            ),
        ]
        let attachments = [
            PromptAttachment(filename: "proposal.pdf", mime: "application/pdf", pageCount: 12),
        ]

        let prompt = ThreadBriefPrompt.taskPrompt(messages: messages, attachments: attachments)

        #expect(prompt.contains("Alice"))
        #expect(prompt.contains("Bob"))
        #expect(prompt.contains("Please review the attached proposal."))
        #expect(prompt.contains("Looks good, approved."))
        #expect(prompt.contains("proposal.pdf"))
        #expect(prompt.contains("12 pages"))
        #expect(prompt.contains("## Thread"))
        #expect(prompt.contains("## Attachments"))
        #expect(prompt.contains("## Output JSON"))
        #expect(prompt.contains("Reply with JSON only."))
    }

    @Test("task prompt omits attachments section when empty")
    func taskPromptNoAttachments() {
        let messages = [
            PromptMessage(
                from: "Charlie",
                sentAt: Date(timeIntervalSince1970: 1_700_000_000),
                bodyText: "Just a quick note."
            ),
        ]

        let prompt = ThreadBriefPrompt.taskPrompt(messages: messages, attachments: [])

        #expect(prompt.contains("Charlie"))
        #expect(!prompt.contains("## Attachments"))
    }

    @Test("task prompt includes output shape without raw JSON Schema")
    func taskPromptIncludesOutputShapeWithoutRawSchema() {
        let prompt = ThreadBriefPrompt.taskPrompt(
            messages: [PromptMessage(from: "X", sentAt: .now, bodyText: "test")],
            attachments: []
        )
        #expect(prompt.contains("confidence"))
        #expect(prompt.contains("evidence"))
        #expect(prompt.contains("summary"))
        #expect(!prompt.contains(#""summary":"...""#))
        #expect(!prompt.contains(#""type": "object""#))
    }

    @Test("task prompt trims long message bodies")
    func taskPromptTrimsLongBodies() {
        let prompt = ThreadBriefPrompt.taskPrompt(
            messages: [
                PromptMessage(
                    from: "X",
                    sentAt: Date(timeIntervalSince1970: 0),
                    bodyText: String(repeating: "x", count: ThreadBriefTask.metadata.maxInputCharacters + 4)
                ),
            ],
            attachments: []
        )

        #expect(prompt.contains("[trimmed 4 characters"))
    }

    @Test("task prompt uses one total body budget across many messages")
    func taskPromptUsesTotalBodyBudgetAcrossMessages() {
        let maxCharacters = ThreadBriefTask.metadata.maxInputCharacters
        let messages = [
            PromptMessage(
                from: "one",
                sentAt: Date(timeIntervalSince1970: 0),
                bodyText: String(repeating: "~", count: maxCharacters + 100)
            ),
            PromptMessage(
                from: "two",
                sentAt: Date(timeIntervalSince1970: 60),
                bodyText: String(repeating: "^", count: maxCharacters + 100)
            ),
            PromptMessage(
                from: "three",
                sentAt: Date(timeIntervalSince1970: 120),
                bodyText: String(repeating: "$", count: maxCharacters + 100)
            ),
        ]
        let prompt = ThreadBriefPrompt.taskPrompt(
            messages: messages,
            attachments: [
                PromptAttachment(filename: "budget.pdf", mime: "application/pdf", pageCount: 3),
            ]
        )

        #expect(prompt.count < maxCharacters * 2)
        #expect(prompt.filter { $0 == "~" }.count == maxCharacters)
        #expect(prompt.filter { $0 == "^" }.isEmpty)
        #expect(prompt.filter { $0 == "$" }.isEmpty)
        #expect(prompt.contains("[trimmed 100 characters"))
        #expect(prompt.contains("[trimmed \(maxCharacters + 100) characters"))
        #expect(prompt.contains("budget.pdf"))
    }

    @Test("small task prompt renders bodies unchanged")
    func smallTaskPromptRendersBodiesUnchanged() {
        let prompt = ThreadBriefPrompt.taskPrompt(
            messages: [
                PromptMessage(
                    from: "small@example.com",
                    sentAt: Date(timeIntervalSince1970: 0),
                    bodyText: "Please confirm the final date."
                ),
            ],
            attachments: []
        )

        #expect(prompt.contains("Please confirm the final date."))
        #expect(!prompt.contains("[trimmed"))
    }

    @Test("parser behavior remains unchanged after budgeting")
    func parserBehaviorRemainsUnchangedAfterBudgeting() throws {
        let brief = try ThreadBriefTask.parse(
            #"{"summary":"Payment failed","request":"Update card","evidence":["Payment failed"],"confidence":0.8}"#
        )

        #expect(brief.summary == "Payment failed")
        #expect(brief.request == "Update card")
        #expect(brief.evidence == ["Payment failed"])
        #expect(brief.confidence == 0.8)
    }
}
