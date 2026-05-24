import Foundation
import Testing
@testable import AIPrompts

@Suite("DraftReplyPrompt")
struct DraftReplyPromptTests {
    @Test func parserDefaultsOptionalMetadataWhenOnlyBodyIsPresent() throws {
        let reply = try DraftReplyParser.parse(#"{"body":"Thanks, I will review this today."}"#)

        #expect(reply.body == "Thanks, I will review this today.")
        #expect(reply.evidenceMessageIDs == [])
        #expect(reply.detectedReplyLanguage == "und")
        #expect(reply.confidence == 0.8)
    }

    @Test func taskPromptTrimsLongMessageBodies() {
        let prompt = DraftReplyPrompt.taskPrompt(
            messages: [
                PromptMessage(
                    from: "sender@example.com",
                    sentAt: Date(timeIntervalSince1970: 0),
                    bodyText: String(repeating: "x", count: DraftReplyTask.metadata.maxInputCharacters + 10)
                ),
            ],
            tone: "warm",
            replyLanguage: "en"
        )

        #expect(prompt.contains("[trimmed 10 characters"))
    }

    @Test func systemPromptContainsConcreteJSONExample() {
        #expect(DraftReplyPrompt.systemPrompt.contains("Example output"))
        #expect(DraftReplyPrompt.systemPrompt.contains("\"body\""))
    }
}
