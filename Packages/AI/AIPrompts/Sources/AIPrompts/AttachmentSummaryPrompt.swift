import Foundation

// MARK: - Parsed Output

public struct ParsedAttachmentKeyField: Sendable, Equatable, Codable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct ParsedAttachmentEvidence: Sendable, Equatable, Codable {
    public let chunkIndex: Int
    public let quote: String

    public init(chunkIndex: Int, quote: String) {
        self.chunkIndex = chunkIndex
        self.quote = quote
    }
}

public struct ParsedAttachmentSummary: Sendable, Equatable, Codable {
    public let summary: String
    public let keyFields: [ParsedAttachmentKeyField]
    public let risks: [String]
    public let nextSteps: [String]
    public let evidence: [ParsedAttachmentEvidence]
    public let confidence: Double

    public init(
        summary: String,
        keyFields: [ParsedAttachmentKeyField] = [],
        risks: [String] = [],
        nextSteps: [String] = [],
        evidence: [ParsedAttachmentEvidence] = [],
        confidence: Double
    ) {
        self.summary = summary
        self.keyFields = keyFields
        self.risks = risks
        self.nextSteps = nextSteps
        self.evidence = evidence
        self.confidence = confidence
    }
}

// MARK: - Prompt Input

public struct PromptAttachmentChunk: Sendable, Equatable {
    public let index: Int
    public let sourceOffset: Int
    public let text: String

    public init(index: Int, sourceOffset: Int, text: String) {
        self.index = index
        self.sourceOffset = sourceOffset
        self.text = text
    }
}

public struct AttachmentSummaryTaskInput: Sendable, Equatable {
    public let filename: String
    public let mime: String
    public let chunks: [PromptAttachmentChunk]

    public init(filename: String, mime: String, chunks: [PromptAttachmentChunk]) {
        self.filename = filename
        self.mime = mime
        self.chunks = chunks
    }
}

// MARK: - Attachment Summary Prompt

public enum AttachmentSummaryTask: PromptTaskDefinition {
    public typealias Input = AttachmentSummaryTaskInput
    public typealias Output = ParsedAttachmentSummary

    public static let metadata = PromptTaskMetadata(
        id: .attachmentSummary,
        promptVersion: "attachment-summary.v1",
        schemaVersion: "attachment-summary.schema.v1",
        modelProfile: "local-gemma-structured-json",
        maxInputCharacters: 12_000,
        maxOutputTokens: 512,
        examples: [
            #"{"summary":"Invoice for EUR 1,840 due on April 15.","keyFields":[{"name":"amount","value":"EUR 1,840"},{"name":"dueDate","value":"April 15"}],"risks":[],"nextSteps":["Schedule payment before April 15"],"evidence":[{"chunkIndex":0,"quote":"Amount due: EUR 1,840"},{"chunkIndex":1,"quote":"Due date: April 15"}],"confidence":0.91}"#,
        ],
        privacyCategory: "local-attachment-text"
    )

    public static let systemPrompt: String = """
        You summarize email attachments for a private on-device mail client. Output ONLY a JSON object — no text before or after. \
        Fields: summary (string), keyFields (array of {"name","value"}), risks (array of strings), nextSteps (array of strings), \
        evidence (array of {"chunkIndex","quote"}), confidence (number 0-1). \
        Rules: never invent facts; every important claim needs evidence from a chunk; quote exact source text; keep response concise; \
        never copy schema words, placeholders, or examples as attachment content.
        """

    public static let outputSeed = #"{"summary":"#

    public static let jsonSchemaString = AttachmentSummarySchema.jsonSchemaString

    public static func renderUserPrompt(_ input: AttachmentSummaryTaskInput) -> String {
        let fixedParts: [String] = [
            "## Output JSON",
            "Keys: summary, keyFields, risks, nextSteps, evidence, confidence.",
            "Evidence entries must include chunkIndex and quote from the extracted text.",
            "Continue the seeded JSON object with the actual attachment summary.",
            "",
            "Reply with JSON only. Do not output schema words or placeholders.",
            "",
            "## Attachment",
            "- Filename: \(input.filename)",
            "- MIME: \(input.mime)",
            "",
            "## Extracted Chunks",
        ]

        let chunkText = input.chunks.map { chunk in
            """
            [chunk \(chunk.index) | offset \(chunk.sourceOffset)]
            \(chunk.text)
            """
        }.joined(separator: "\n")

        return PromptTextBudget.renderedPrompt(
            fixedParts: fixedParts,
            budgetedTail: chunkText,
            maxCharacters: metadata.maxInputCharacters
        )
    }

    public static func parse(_ rawOutput: String) throws -> ParsedAttachmentSummary {
        try AttachmentSummaryParser.parse(rawOutput)
    }
}

public enum AttachmentSummarySchema {
    public static let jsonSchemaString: String = """
        {
          "type": "object",
          "properties": {
            "summary":    { "type": "string" },
            "keyFields":  { "type": "array", "items": { "type": "object", "properties": {
              "name": { "type": "string" },
              "value": { "type": "string" }
            }, "required": ["name", "value"], "additionalProperties": false } },
            "risks":      { "type": "array", "items": { "type": "string" } },
            "nextSteps":  { "type": "array", "items": { "type": "string" } },
            "evidence":   { "type": "array", "items": { "type": "object", "properties": {
              "chunkIndex": { "type": "integer" },
              "quote": { "type": "string" }
            }, "required": ["chunkIndex", "quote"], "additionalProperties": false } },
            "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
          },
          "required": ["summary", "keyFields", "risks", "nextSteps", "evidence", "confidence"],
          "additionalProperties": false
        }
        """
}

public enum AttachmentSummaryParser {
    public enum ParseError: Error, Sendable, Equatable {
        case invalidJSON(String)
        case schemaViolation(String)
    }

    public static func parse(_ rawOutput: String) throws -> ParsedAttachmentSummary {
        var firstSchemaViolation: String?

        for json in PromptJSON.objectCandidates(from: rawOutput) {
            guard let raw = decodeRawAttachmentSummary(from: json) else { continue }

            guard PromptJSON.isMeaningfulTaskText(raw.summary) else {
                firstSchemaViolation = firstSchemaViolation ?? "summary must not be empty"
                continue
            }
            guard raw.confidence >= 0, raw.confidence <= 1 else {
                firstSchemaViolation = firstSchemaViolation ?? "confidence must be between 0 and 1, got \(raw.confidence)"
                continue
            }
            guard raw.evidence.allSatisfy({ !$0.quote.isEmpty && $0.chunkIndex >= 0 }) else {
                firstSchemaViolation = firstSchemaViolation
                    ?? "evidence entries must include non-empty quotes and non-negative chunk indexes"
                continue
            }

            return ParsedAttachmentSummary(
                summary: raw.summary,
                keyFields: raw.keyFields,
                risks: raw.risks,
                nextSteps: raw.nextSteps,
                evidence: raw.evidence,
                confidence: raw.confidence
            )
        }

        if let firstSchemaViolation {
            throw ParseError.schemaViolation(firstSchemaViolation)
        }

        let truncated = String(rawOutput.prefix(200))
        throw ParseError.invalidJSON(truncated)
    }

    private static func decodeRawAttachmentSummary(from json: String) -> RawAttachmentSummary? {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        if let raw = try? decoder.decode(RawAttachmentSummary.self, from: data) {
            return raw
        }
        if let wrapper = try? decoder.decode(RawAttachmentSummaryWrapper.self, from: data) {
            return wrapper.summary
        }
        return nil
    }
}

private struct RawAttachmentSummary: Decodable {
    let summary: String
    let keyFields: [ParsedAttachmentKeyField]
    let risks: [String]
    let nextSteps: [String]
    let evidence: [ParsedAttachmentEvidence]
    let confidence: Double

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case summary, keyFields, risks, nextSteps, evidence, confidence
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
        summary = try known.decode(String.self, forKey: .summary)
        keyFields = try known.decode([ParsedAttachmentKeyField].self, forKey: .keyFields)
        risks = try known.decode([String].self, forKey: .risks)
        nextSteps = try known.decode([String].self, forKey: .nextSteps)
        evidence = try known.decode([ParsedAttachmentEvidence].self, forKey: .evidence)
        confidence = try known.decode(Double.self, forKey: .confidence)
    }
}

private struct RawAttachmentSummaryWrapper: Decodable {
    let summary: RawAttachmentSummary?

    enum CodingKeys: String, CodingKey {
        case attachmentSummary
        case attachment_summary
        case summary
        case result
        case response
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeFirstSummary(
            forKeys: [.attachmentSummary, .attachment_summary, .summary, .result, .response]
        )
    }
}

private extension KeyedDecodingContainer where K == RawAttachmentSummaryWrapper.CodingKeys {
    func decodeFirstSummary(forKeys keys: [K]) throws -> RawAttachmentSummary? {
        for key in keys where contains(key) {
            if let value = try? decode(RawAttachmentSummary.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}
