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
        var firstSchemaViolation: String?

        for json in PromptJSON.objectCandidates(from: rawOutput) {
            guard let raw = decodeRawBrief(from: json) else { continue }

            guard raw.hasMeaningfulContent else {
                firstSchemaViolation = firstSchemaViolation ?? "brief must contain at least one meaningful field"
                continue
            }

            let evidence = raw.evidence ?? []
            let confidence = raw.confidence ?? 0.7

            guard confidence >= 0, confidence <= 1 else {
                firstSchemaViolation = firstSchemaViolation ?? "confidence must be between 0 and 1, got \(confidence)"
                continue
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

        if let firstSchemaViolation {
            throw ParseError.schemaViolation(firstSchemaViolation)
        }

        if let fallback = fallbackBrief(from: rawOutput) {
            return fallback
        }

        let truncated = String(rawOutput.prefix(200))
        throw ParseError.invalidJSON(truncated)
    }

    // MARK: - Private

    private static func decodeRawBrief(from json: String) -> RawBrief? {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        if let raw = try? decoder.decode(RawBrief.self, from: data), raw.hasMeaningfulContent {
            return raw
        }
        if let wrapper = try? decoder.decode(RawBriefWrapper.self, from: data) {
            return wrapper.brief
        }
        return try? decoder.decode(RawBrief.self, from: data)
    }

    private static func fallbackBrief(from rawOutput: String) -> ParsedThreadBrief? {
        if let summary = PromptJSON.seededPlainTextFallback(from: rawOutput) {
            return ParsedThreadBrief(summary: summary, evidence: [], confidence: 0.45)
        }

        let summary = PromptJSON.firstStringValue(in: rawOutput, forKeys: ["summary"])
        let request = PromptJSON.firstStringValue(in: rawOutput, forKeys: ["request"])
        let deadline = PromptJSON.firstStringValue(in: rawOutput, forKeys: ["deadline"])
        let risk = PromptJSON.firstStringValue(in: rawOutput, forKeys: ["risk"])
        let nextStep = PromptJSON.firstStringValue(
            in: rawOutput,
            forKeys: ["nextStep", "next_step", "nextSteps", "next_steps"]
        )

        guard [summary, request, deadline, risk, nextStep].contains(where: { $0 != nil }) else {
            return nil
        }

        return ParsedThreadBrief(
            summary: summary,
            request: request,
            deadline: deadline,
            risk: risk,
            nextStep: nextStep,
            evidence: [],
            confidence: 0.55
        )
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

private struct RawBriefWrapper: Decodable {
    let brief: RawBrief?

    enum CodingKeys: String, CodingKey {
        case brief
        case threadBrief
        case thread_brief
        case result
        case response
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brief = try container.decodeFirstBrief(
            forKeys: [.brief, .threadBrief, .thread_brief, .result, .response]
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

private extension KeyedDecodingContainer where K == RawBriefWrapper.CodingKeys {
    func decodeFirstBrief(forKeys keys: [K]) throws -> RawBrief? {
        for key in keys where contains(key) {
            if let value = try? decode(RawBrief.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}
