import Foundation

// MARK: - Prompt Task Registry

public enum PromptTaskID: String, CaseIterable, Sendable, Codable {
    case threadBrief
    case draftReply
    case attachmentSummary
}

public struct PromptTaskMetadata: Sendable, Equatable, Codable {
    public let id: PromptTaskID
    public let promptVersion: String
    public let schemaVersion: String
    public let modelProfile: String
    public let maxInputCharacters: Int
    public let maxOutputTokens: Int
    public let examples: [String]
    public let privacyCategory: String

    public init(
        id: PromptTaskID,
        promptVersion: String,
        schemaVersion: String,
        modelProfile: String,
        maxInputCharacters: Int,
        maxOutputTokens: Int,
        examples: [String],
        privacyCategory: String
    ) {
        self.id = id
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.modelProfile = modelProfile
        self.maxInputCharacters = maxInputCharacters
        self.maxOutputTokens = maxOutputTokens
        self.examples = examples
        self.privacyCategory = privacyCategory
    }
}

public protocol PromptTaskDefinition {
    associatedtype Input
    associatedtype Output

    static var metadata: PromptTaskMetadata { get }
    static var systemPrompt: String { get }
    static var jsonSchemaString: String { get }

    static func renderUserPrompt(_ input: Input) -> String
    static func parse(_ rawOutput: String) throws -> Output
}

public enum PromptParseError: Error, Sendable, Equatable {
    case invalidJSON(String)
    case schemaViolation(String)
}

public enum PromptTaskRegistry {
    public static let allMetadata: [PromptTaskMetadata] = [
        ThreadBriefTask.metadata,
        DraftReplyTask.metadata,
        AttachmentSummaryTask.metadata,
    ]

    public static func metadata(for id: PromptTaskID) -> PromptTaskMetadata? {
        allMetadata.first { $0.id == id }
    }
}

// MARK: - Text Budget

public enum PromptTextBudget {
    public static func trimmed(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let prefix = text.prefix(maxCharacters)
        let omitted = text.count - maxCharacters
        return "\(prefix)\n\n[trimmed \(omitted) characters to fit the local model context]"
    }

    static func trimmedMessageBody(_ text: String, maxCharacters: Int) -> String {
        trimmed(text, maxCharacters: maxCharacters)
    }
}

// MARK: - Shared JSON Extraction

enum PromptJSON {
    static func extractObject(from raw: String) -> String {
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

        guard let end = matchEnd else { return text }
        return String(text[start...end])
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}
