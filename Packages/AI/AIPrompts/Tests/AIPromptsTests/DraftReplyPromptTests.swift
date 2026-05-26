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

        #expect(prompt.count <= DraftReplyTask.metadata.maxInputCharacters)
        #expect(prompt.contains("[trimmed "))
    }

    @Test func taskPromptUsesOneTotalRenderedBudgetAcrossManyMessages() {
        let maxCharacters = DraftReplyTask.metadata.maxInputCharacters
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

        let prompt = DraftReplyPrompt.taskPrompt(
            messages: messages,
            tone: "concise",
            replyLanguage: "en"
        )

        #expect(prompt.count <= maxCharacters)
        #expect(prompt.filter { $0 == "~" }.count > 0)
        #expect(prompt.filter { $0 == "~" }.count < maxCharacters)
        #expect(prompt.filter { $0 == "^" }.isEmpty)
        #expect(prompt.filter { $0 == "$" }.isEmpty)
        #expect(prompt.contains("[trimmed "))
        #expect(prompt.contains("## Output JSON"))
        #expect(prompt.contains("msg_1"))
    }

    @Test func taskPromptCapsManyEmptyMessageHeaders() {
        let maxCharacters = DraftReplyTask.metadata.maxInputCharacters
        let prompt = DraftReplyPrompt.taskPrompt(
            messages: (0..<800).map { index in
                PromptMessage(
                    from: "sender-\(index)@example.com",
                    sentAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    bodyText: ""
                )
            },
            tone: "concise",
            replyLanguage: "en"
        )

        #expect(prompt.count <= maxCharacters)
        #expect(prompt.contains("## Output JSON"))
    }

    @Test func smallTaskPromptRendersBodiesUnchanged() {
        let prompt = DraftReplyPrompt.taskPrompt(
            messages: [
                PromptMessage(
                    from: "small@example.com",
                    sentAt: Date(timeIntervalSince1970: 0),
                    bodyText: "Please send the signed copy today."
                ),
            ],
            tone: "warm",
            replyLanguage: "en"
        )

        #expect(prompt.contains("Please send the signed copy today."))
        #expect(!prompt.contains("[trimmed"))
    }

    @Test func parserBehaviorRemainsUnchangedAfterBudgeting() throws {
        let reply = try DraftReplyTask.parse(
            #"{"body":"Thanks, I will send the signed copy today.","evidenceMessageIDs":["msg_1"],"detectedReplyLanguage":"en","confidence":0.83}"#
        )

        #expect(reply.body == "Thanks, I will send the signed copy today.")
        #expect(reply.evidenceMessageIDs == ["msg_1"])
        #expect(reply.detectedReplyLanguage == "en")
        #expect(reply.confidence == 0.83)
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
