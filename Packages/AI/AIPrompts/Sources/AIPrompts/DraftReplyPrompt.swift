import Foundation

// MARK: - Parsed Output

public struct ParsedThreadReply: Sendable, Equatable, Codable {
    public let body: String
    public let evidenceMessageIDs: [String]
    public let detectedReplyLanguage: String
    public let confidence: Double

    public init(
        body: String,
        evidenceMessageIDs: [String] = [],
        detectedReplyLanguage: String = "en",
        confidence: Double = 0.8
    ) {
        self.body = body
        self.evidenceMessageIDs = evidenceMessageIDs
        self.detectedReplyLanguage = detectedReplyLanguage
        self.confidence = confidence
    }
}

// MARK: - Draft Reply Prompt

public struct DraftReplyTaskInput: Sendable {
    public let messages: [PromptMessage]
    public let tone: String
    public let replyLanguage: String

    public init(messages: [PromptMessage], tone: String, replyLanguage: String) {
        self.messages = messages
        self.tone = tone
        self.replyLanguage = replyLanguage
    }
}

public enum DraftReplyTask: PromptTaskDefinition {
    public typealias Input = DraftReplyTaskInput
    public typealias Output = ParsedThreadReply

    public static let metadata = PromptTaskMetadata(
        id: .draftReply,
        promptVersion: "draft-reply.v2",
        schemaVersion: "draft-reply.schema.v2",
        modelProfile: "local-gemma-structured-json",
        maxInputCharacters: 5_000,
        maxOutputTokens: 512,
        examples: [
            #"{"body":"Thanks for the update. I will review the contract today and get back to you by Friday.","evidenceMessageIDs":["msg_1"],"detectedReplyLanguage":"en","confidence":0.86}"#,
        ],
        privacyCategory: "local-email-thread"
    )

    public static let systemPrompt: String = """
        You are an email reply assistant. Output ONLY a JSON object — no text before or after. \
        Fields: body (string, the reply text), evidenceMessageIDs (array of message indices like "msg_1"), \
        detectedReplyLanguage (BCP-47 code like "en" or "ru"), confidence (number 0-1). \
        Rules: write a natural reply to the thread; match the tone instruction; respond in the specified language; \
        never invent facts not in the thread; keep the reply concise and actionable; never copy schema words, \
        placeholders, or examples as the reply body.
        """

    public static let outputSeed = #"{"body":"#

    public static let jsonSchemaString = DraftReplySchema.jsonSchemaString

    public static func renderUserPrompt(_ input: DraftReplyTaskInput) -> String {
        var parts: [String] = []

        parts.append("## Thread")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let budgetedBodies = PromptTextBudget.trimmedSections(
            input.messages.map(\.bodyText),
            maxCharacters: metadata.maxInputCharacters
        )
        for (idx, pair) in zip(input.messages, budgetedBodies).enumerated() {
            let (msg, body) = pair
            let ts = formatter.string(from: msg.sentAt)
            parts.append("""
                [msg_\(idx + 1) | From: \(msg.from) | \(ts)]
                \(body)
                """)
        }

        parts.append("")
        parts.append("## Instructions")
        parts.append("- Tone: \(input.tone)")
        parts.append("- Respond in: \(input.replyLanguage)")
        parts.append("")
        parts.append("## Output JSON")
        parts.append("Keys: body, evidenceMessageIDs, detectedReplyLanguage, confidence.")
        parts.append("Continue the seeded JSON object with the actual reply text as body.")
        parts.append("")
        parts.append("Reply with JSON only. Do not output schema words or placeholders.")

        return parts.joined(separator: "\n")
    }

    public static func parse(_ rawOutput: String) throws -> ParsedThreadReply {
        try DraftReplyParser.parse(rawOutput)
    }
}

public enum DraftReplyPrompt {
    public static let systemPrompt = DraftReplyTask.systemPrompt

    public static func taskPrompt(
        messages: [PromptMessage],
        tone: String,
        replyLanguage: String
    ) -> String {
        DraftReplyTask.renderUserPrompt(
            DraftReplyTaskInput(messages: messages, tone: tone, replyLanguage: replyLanguage)
        )
    }
}

// MARK: - JSON Schema

public enum DraftReplySchema {
    public static let jsonSchemaString: String = """
        {
          "type": "object",
          "properties": {
            "body":                  { "type": "string" },
            "evidenceMessageIDs":    { "type": "array", "items": { "type": "string" } },
            "detectedReplyLanguage": { "type": "string" },
            "confidence":            { "type": "number", "minimum": 0, "maximum": 1 }
          },
          "required": ["body"],
          "additionalProperties": false
        }
        """
}

// MARK: - Parser

public enum DraftReplyParser {

    public enum ParseError: Error, Sendable, Equatable {
        case invalidJSON(String)
        case schemaViolation(String)
    }

    public static func parse(_ rawOutput: String) throws -> ParsedThreadReply {
        var firstSchemaViolation: String?

        for json in PromptJSON.objectCandidates(from: rawOutput) {
            guard let raw = decodeRawReply(from: json) else { continue }

            guard PromptJSON.isMeaningfulTaskText(raw.body) else {
                firstSchemaViolation = firstSchemaViolation ?? "body must not be empty"
                continue
            }

            let confidence = raw.confidence ?? 0.8
            guard confidence >= 0, confidence <= 1 else {
                firstSchemaViolation = firstSchemaViolation ?? "confidence must be between 0 and 1, got \(confidence)"
                continue
            }

            return ParsedThreadReply(
                body: raw.body,
                evidenceMessageIDs: raw.evidenceMessageIDs ?? [],
                detectedReplyLanguage: raw.detectedReplyLanguage ?? "und",
                confidence: confidence
            )
        }

        if let plainReply = parsePlainReplyFallback(rawOutput) {
            return plainReply
        }

        if let firstSchemaViolation {
            throw ParseError.schemaViolation(firstSchemaViolation)
        }

        if let body = PromptJSON.firstStringValue(in: rawOutput, forKeys: ["body", "reply", "draft", "message"]) {
            return ParsedThreadReply(body: body, evidenceMessageIDs: [], detectedReplyLanguage: "und", confidence: 0.55)
        }

        let truncated = String(rawOutput.prefix(200))
        throw ParseError.invalidJSON(truncated)
    }

    private static func decodeRawReply(from json: String) -> RawReply? {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        if let raw = try? decoder.decode(RawReply.self, from: data), !raw.body.isEmpty {
            return raw
        }
        if let wrapper = try? decoder.decode(RawReplyWrapper.self, from: data) {
            return wrapper.reply
        }
        return try? decoder.decode(RawReply.self, from: data)
    }

    private static func parsePlainReplyFallback(_ rawOutput: String) -> ParsedThreadReply? {
        if let body = PromptJSON.seededPlainTextFallback(from: rawOutput) {
            return ParsedThreadReply(body: body, evidenceMessageIDs: [], detectedReplyLanguage: "und", confidence: 0.5)
        }

        guard !rawOutput.contains("{") else {
            return nil
        }

        var body = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            if let firstNewline = body.firstIndex(of: "\n") {
                body = String(body[body.index(after: firstNewline)...])
            }
            if body.hasSuffix("```") {
                body = String(body.dropLast(3))
            }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard PromptJSON.isMeaningfulTaskText(body) else { return nil }
        return ParsedThreadReply(body: body, evidenceMessageIDs: [], detectedReplyLanguage: "und", confidence: 0.6)
    }
}

private struct RawReply: Decodable {
    let body: String
    let evidenceMessageIDs: [String]?
    let detectedReplyLanguage: String?
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case body
        case reply
        case draft
        case message
        case evidenceMessageIDs
        case evidenceMessageIds
        case evidenceMessageIDsSnake = "evidence_message_ids"
        case detectedReplyLanguage
        case detectedReplyLanguageSnake = "detected_reply_language"
        case language
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedBody = try container.decodeStringIfPresent(forKeys: [.body, .reply, .draft, .message])
        body = decodedBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        evidenceMessageIDs = try container.decodeStringArrayIfPresent(
            forKeys: [.evidenceMessageIDs, .evidenceMessageIds, .evidenceMessageIDsSnake]
        )
        detectedReplyLanguage = try container.decodeStringIfPresent(
            forKeys: [.detectedReplyLanguage, .detectedReplyLanguageSnake, .language]
        )
        confidence = try container.decodeDoubleIfPresent(forKeys: [.confidence])
    }
}

private struct RawReplyWrapper: Decodable {
    let reply: RawReply?

    enum CodingKeys: String, CodingKey {
        case reply
        case draft
        case message
        case response
        case result
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decodeFirstReply(
            forKeys: [.reply, .draft, .message, .response, .result]
        )
    }
}

private extension KeyedDecodingContainer where K == RawReply.CodingKeys {
    func decodeStringIfPresent(forKeys keys: [K]) throws -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeStringArrayIfPresent(forKeys keys: [K]) throws -> [String]? {
        for key in keys {
            if let value = try? decodeIfPresent([String].self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                return [value]
            }
        }
        return nil
    }

    func decodeDoubleIfPresent(forKeys keys: [K]) throws -> Double? {
        for key in keys {
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let value = try? decodeIfPresent(String.self, forKey: key),
               let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return nil
    }
}

private extension KeyedDecodingContainer where K == RawReplyWrapper.CodingKeys {
    func decodeFirstReply(forKeys keys: [K]) throws -> RawReply? {
        for key in keys where contains(key) {
            if let value = try? decode(RawReply.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}
