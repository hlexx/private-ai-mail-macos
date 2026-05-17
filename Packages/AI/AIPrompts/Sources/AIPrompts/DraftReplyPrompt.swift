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

public enum DraftReplyPrompt {

    public static let systemPrompt: String = """
        You are an email reply assistant. Output ONLY a JSON object — no text before or after. \
        Fields: body (string, the reply text), evidenceMessageIDs (array of message indices like "msg_1"), \
        detectedReplyLanguage (BCP-47 code like "en" or "ru"), confidence (number 0-1). \
        Rules: write a natural reply to the thread; match the tone instruction; respond in the specified language; \
        never invent facts not in the thread; keep the reply concise and actionable.
        """

    public static func taskPrompt(
        messages: [PromptMessage],
        tone: String,
        replyLanguage: String
    ) -> String {
        var parts: [String] = []

        parts.append("## Thread")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for (idx, msg) in messages.enumerated() {
            let ts = formatter.string(from: msg.sentAt)
            parts.append("""
                [msg_\(idx + 1) | From: \(msg.from) | \(ts)]
                \(msg.bodyText)
                """)
        }

        parts.append("")
        parts.append("## Instructions")
        parts.append("- Tone: \(tone)")
        parts.append("- Respond in: \(replyLanguage)")
        parts.append("")
        parts.append("## Output Schema")
        parts.append(DraftReplySchema.jsonSchemaString)
        parts.append("")
        parts.append("Reply with the JSON object only.")

        return parts.joined(separator: "\n")
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
          "required": ["body", "evidenceMessageIDs", "detectedReplyLanguage", "confidence"],
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
        let json = extractJSON(from: rawOutput)
        let data = Data(json.utf8)

        let raw: RawReply
        do {
            raw = try JSONDecoder().decode(RawReply.self, from: data)
        } catch {
            let truncated = String(rawOutput.prefix(200))
            throw ParseError.invalidJSON(truncated)
        }

        guard !raw.body.isEmpty else {
            throw ParseError.schemaViolation("body must not be empty")
        }

        guard raw.confidence >= 0, raw.confidence <= 1 else {
            throw ParseError.schemaViolation("confidence must be between 0 and 1, got \(raw.confidence)")
        }

        return ParsedThreadReply(
            body: raw.body,
            evidenceMessageIDs: raw.evidenceMessageIDs,
            detectedReplyLanguage: raw.detectedReplyLanguage,
            confidence: raw.confidence
        )
    }

    private static func extractJSON(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if text.hasSuffix("```") {
                text = String(text.dropLast(3))
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = text.firstIndex(of: "{") else { return text }

        var depth = 0
        var inString = false
        var escaped = false
        var matchEnd: String.Index?

        for i in text.indices[start...] {
            let ch = text[i]
            if escaped { escaped = false; continue }
            if ch == "\\" && inString { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { matchEnd = i; break }
            }
        }

        guard let end = matchEnd else { return text }
        return String(text[start...end])
    }
}

private struct RawReply: Decodable {
    let body: String
    let evidenceMessageIDs: [String]
    let detectedReplyLanguage: String
    let confidence: Double
}
