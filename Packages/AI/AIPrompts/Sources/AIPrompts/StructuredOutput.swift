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

        guard raw.hasMeaningfulContent else {
            throw ParseError.schemaViolation("brief must contain at least one meaningful field")
        }

        let evidence = raw.evidence ?? []
        let confidence = raw.confidence ?? 0.7

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
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
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

// Tolerant decoding struct: the prompt schema remains strict, but small local
// models sometimes omit metadata or use common aliases. Preserve useful briefs
// and let the registry/tests enforce the preferred schema separately.
private struct RawBrief: Decodable {
    let summary: String?
    let request: String?
    let deadline: String?
    let risk: String?
    let nextStep: String?
    let evidence: [String]?
    let confidence: Double?

    var hasMeaningfulContent: Bool {
        [summary, request, deadline, risk, nextStep].contains { field in
            field?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } || evidence?.isEmpty == false
    }

    enum CodingKeys: String, CodingKey {
        case summary, request, deadline, risk, nextStep, evidence, confidence
        case next_step
        case nextSteps
        case next_steps
        case confidenceScore
        case confidence_score
    }

    init(from decoder: any Decoder) throws {
        let known = try decoder.container(keyedBy: CodingKeys.self)
        summary = try known.decodeIfPresent(String.self, forKey: .summary)
        request = try known.decodeIfPresent(String.self, forKey: .request)
        deadline = try known.decodeIfPresent(String.self, forKey: .deadline)
        risk = try known.decodeIfPresent(String.self, forKey: .risk)
        nextStep = try known.decodeFirstString(
            forKeys: [CodingKeys.nextStep, .next_step, .nextSteps, .next_steps]
        )
        evidence = try known.decodeFlexibleStringArrayIfPresent(forKey: .evidence)
        confidence = try known.decodeFirstDouble(
            forKeys: [CodingKeys.confidence, .confidenceScore, .confidence_score]
        )
    }
}

private extension KeyedDecodingContainer where K == RawBrief.CodingKeys {
    func decodeFirstString(forKeys keys: [K]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeFirstDouble(forKeys keys: [K]) throws -> Double? {
        for key in keys {
            if let value = try decodeFlexibleDoubleIfPresent(forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKey key: K) throws -> Double? {
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Double(string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
        }
        return nil
    }

    func decodeFlexibleStringArrayIfPresent(forKey key: K) throws -> [String]? {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        return nil
    }
}
