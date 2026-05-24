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
        #expect(prompt.contains("## Output Schema"))
        #expect(prompt.contains("Reply with the JSON object only."))
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

    @Test("task prompt includes JSON schema")
    func taskPromptIncludesSchema() {
        let prompt = ThreadBriefPrompt.taskPrompt(
            messages: [PromptMessage(from: "X", sentAt: .now, bodyText: "test")],
            attachments: []
        )
        #expect(prompt.contains("\"confidence\""))
        #expect(prompt.contains("\"evidence\""))
        #expect(prompt.contains("\"summary\""))
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
}
