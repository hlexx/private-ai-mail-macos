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

        #expect(prompt.contains("[trimmed 10 characters"))
    }

    @Test func systemPromptContainsConcreteJSONExample() {
        #expect(DraftReplyPrompt.systemPrompt.contains("Example output"))
        #expect(DraftReplyPrompt.systemPrompt.contains("\"body\""))
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
