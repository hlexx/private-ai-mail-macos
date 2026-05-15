import Foundation

// MARK: - JSON Schema

public enum ThreadBriefSchema {
    public static let jsonSchemaString: String = """
        {
          "type": "object",
          "properties": {
            "summary":    { "type": ["string", "null"] },
            "request":    { "type": ["string", "null"] },
            "deadline":   { "type": ["string", "null"] },
            "risk":       { "type": ["string", "null"] },
            "nextStep":   { "type": ["string", "null"] },
            "evidence":   { "type": "array", "items": { "type": "string" } },
            "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
          },
          "required": ["evidence", "confidence"],
          "additionalProperties": false
        }
        """
}

// MARK: - Parsed Output

public struct ParsedThreadBrief: Sendable, Equatable, Codable {
    public let summary: String?
    public let request: String?
    public let deadline: String?
    public let risk: String?
    public let nextStep: String?
    public let evidence: [String]
    public let confidence: Double

    public init(
        summary: String? = nil,
        request: String? = nil,
        deadline: String? = nil,
        risk: String? = nil,
        nextStep: String? = nil,
        evidence: [String] = [],
        confidence: Double
    ) {
        self.summary = summary
        self.request = request
        self.deadline = deadline
        self.risk = risk
        self.nextStep = nextStep
        self.evidence = evidence
        self.confidence = confidence
    }
}

// MARK: - Parser

public enum ThreadBriefParser {

    public enum ParseError: Error, Sendable, Equatable {
        case invalidJSON(String)
        case schemaViolation(String)
    }

    /// Parse raw LLM output into a `ParsedThreadBrief`.
    /// Extracts the first JSON object from the output (handles markdown fences).
    /// Throws `ParseError.invalidJSON` for malformed JSON,
    /// `ParseError.schemaViolation` for missing required fields or out-of-range confidence.
    public static func parse(_ rawOutput: String) throws -> ParsedThreadBrief {
        let json = extractJSON(from: rawOutput)

        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        let raw: RawBrief
        do {
            raw = try decoder.decode(RawBrief.self, from: data)
        } catch {
            let truncated = String(rawOutput.prefix(200))
            throw ParseError.invalidJSON(truncated)
        }

        guard let evidence = raw.evidence else {
            throw ParseError.schemaViolation("missing required field: evidence")
        }

        guard let confidence = raw.confidence else {
            throw ParseError.schemaViolation("missing required field: confidence")
        }

        guard confidence >= 0, confidence <= 1 else {
            throw ParseError.schemaViolation("confidence must be between 0 and 1, got \(confidence)")
        }

        return ParsedThreadBrief(
            summary: raw.summary,
            request: raw.request,
            deadline: raw.deadline,
            risk: raw.risk,
            nextStep: raw.nextStep,
            evidence: evidence,
            confidence: confidence
        )
    }

    // MARK: - Private

    /// Extract the first JSON object from raw LLM output.
    /// Handles markdown code fences (```json ... ```) and leading/trailing whitespace.
    private static func extractJSON(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if text.hasSuffix("```") {
                text = String(text.dropLast(3))
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find first { and its matching } using brace-depth counting
        guard let start = text.firstIndex(of: "{") else {
            return text
        }

        var depth = 0
        var inString = false
        var escaped = false
        var matchEnd: String.Index?

        for i in text.indices[start...] {
            let ch = text[i]
            if escaped {
                escaped = false
                continue
            }
            if ch == "\\" && inString {
                escaped = true
                continue
            }
            if ch == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    matchEnd = i
                    break
                }
            }
        }

        guard let end = matchEnd else {
            return text
        }

        return String(text[start...end])
    }
}

// Strict decoding struct: all fields optional for validation, rejects unknown keys
private struct RawBrief: Decodable {
    let summary: String?
    let request: String?
    let deadline: String?
    let risk: String?
    let nextStep: String?
    let evidence: [String]?
    let confidence: Double?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case summary, request, deadline, risk, nextStep, evidence, confidence
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = container.allKeys.filter { !allowed.contains($0.stringValue) }
        if let extra = unknown.first {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [extra], debugDescription: "unknown field: \(extra.stringValue)")
            )
        }

        let known = try decoder.container(keyedBy: CodingKeys.self)
        summary = try known.decodeIfPresent(String.self, forKey: .summary)
        request = try known.decodeIfPresent(String.self, forKey: .request)
        deadline = try known.decodeIfPresent(String.self, forKey: .deadline)
        risk = try known.decodeIfPresent(String.self, forKey: .risk)
        nextStep = try known.decodeIfPresent(String.self, forKey: .nextStep)
        evidence = try known.decodeIfPresent([String].self, forKey: .evidence)
        confidence = try known.decodeIfPresent(Double.self, forKey: .confidence)
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}
