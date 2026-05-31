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

    @Test func parserAcceptsCommonReplyAliasesAndStringMetadata() throws {
        let reply = try DraftReplyParser.parse(
            #"{"reply":"Thanks, I will review this today.","evidence_message_ids":"msg_1","language":"en","confidence":"0.7"}"#
        )

        #expect(reply.body == "Thanks, I will review this today.")
        #expect(reply.evidenceMessageIDs == ["msg_1"])
        #expect(reply.detectedReplyLanguage == "en")
        #expect(reply.confidence == 0.7)
    }

    @Test func parserAcceptsSeededDuplicateOpeningBrace() throws {
        let reply = try DraftReplyParser.parse(#"{{"body":"Thanks, I will update it today.","confidence":0.72}}"#)

        #expect(reply.body == "Thanks, I will update it today.")
        #expect(reply.confidence == 0.72)
    }

    @Test func parserAcceptsNestedReplyObject() throws {
        let reply = try DraftReplyParser.parse(
            #"{"reply":{"body":"Thanks, I will update the payment method today.","language":"en","confidence":"0.74"}}"#
        )

        #expect(reply.body == "Thanks, I will update the payment method today.")
        #expect(reply.detectedReplyLanguage == "en")
        #expect(reply.confidence == 0.74)
    }

    @Test func parserAcceptsSeededPlainTextReplyFallback() throws {
        let reply = try DraftReplyParser.parse("{Thanks, I will update the payment method today.")

        #expect(reply.body == "Thanks, I will update the payment method today.")
        #expect(reply.confidence == 0.5)
    }

    @Test func parserSalvagesCompleteBodyFromTruncatedJSONObject() throws {
        let reply = try DraftReplyParser.parse(#"{"body":"Thanks, I will update it today.","confidence":0.8"#)

        #expect(reply.body == "Thanks, I will update it today.")
        #expect(reply.confidence == 0.55)
    }

    @Test func parserAcceptsPlainTextReplyFallback() throws {
        let reply = try DraftReplyParser.parse("Thanks, I will review this today.")

        #expect(reply.body == "Thanks, I will review this today.")
        #expect(reply.evidenceMessageIDs == [])
        #expect(reply.detectedReplyLanguage == "und")
        #expect(reply.confidence == 0.6)
    }

    @Test func parserRejectsSchemaEchoAsDraftBody() throws {
        #expect(throws: DraftReplyParser.ParseError.self) {
            try DraftReplyParser.parse(DraftReplySchema.jsonSchemaString)
        }
    }

    @Test func parserRejectsSchemaKeywordBody() throws {
        #expect(throws: DraftReplyParser.ParseError.self) {
            try DraftReplyParser.parse(#"{"body":"type","confidence":0.5}"#)
        }
    }

    @Test func parserRejectsPlaceholderBody() throws {
        #expect(throws: DraftReplyParser.ParseError.self) {
            try DraftReplyParser.parse(#"{"body":"...","confidence":0.5}"#)
        }
    }

    @Test func parserStillRejectsMalformedJSONAttempts() throws {
        #expect(throws: DraftReplyParser.ParseError.self) {
            try DraftReplyParser.parse(#"{"reply":"unterminated"#)
        }
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

        #expect(prompt.contains("[trimmed"))
        #expect(prompt.count <= DraftReplyTask.metadata.maxInputCharacters)
    }

    @Test func taskPromptAppliesRenderedBudgetAndKeepsNewestMessages() {
        let messages = [
            PromptMessage(
                from: "oldest@example.com",
                sentAt: Date(timeIntervalSince1970: 1),
                bodyText: "oldest context " + String(repeating: "o", count: DraftReplyTask.metadata.maxInputCharacters)
            ),
            PromptMessage(
                from: "middle@example.com",
                sentAt: Date(timeIntervalSince1970: 2),
                bodyText: "middle context " + String(repeating: "m", count: DraftReplyTask.metadata.maxInputCharacters)
            ),
            PromptMessage(
                from: "latest@example.com",
                sentAt: Date(timeIntervalSince1970: 3),
                bodyText: "latest ask needs answer " + String(repeating: "l", count: DraftReplyTask.metadata.maxInputCharacters)
            ),
        ]

        let prompt = DraftReplyPrompt.taskPrompt(
            messages: messages,
            tone: "warm",
            replyLanguage: "en"
        )

        #expect(prompt.contains("[trimmed"))
        #expect(prompt.count <= DraftReplyTask.metadata.maxInputCharacters)
        #expect(prompt.contains("latest ask needs answer"))
        #expect(!prompt.contains("oldest context"))
        #expect(prompt.contains("## Instructions"))
    }

    @Test func systemPromptDoesNotIncludeCopyableExampleBody() {
        #expect(DraftReplyPrompt.systemPrompt.contains("body"))
        #expect(!DraftReplyPrompt.systemPrompt.contains("contract today"))
        #expect(!DraftReplyPrompt.systemPrompt.contains("Example output"))
    }

    @Test func taskPromptUsesCompactOutputShapeWithoutRawJSONSchema() {
        let prompt = DraftReplyPrompt.taskPrompt(
            messages: [
                PromptMessage(from: "sender@example.com", sentAt: Date(timeIntervalSince1970: 0), bodyText: "Hello"),
            ],
            tone: "warm",
            replyLanguage: "en"
        )

        #expect(prompt.contains("## Output JSON"))
        #expect(prompt.contains("body"))
        #expect(!prompt.contains(#""body":"...""#))
        #expect(!prompt.contains(#""type": "object""#))
    }
}
