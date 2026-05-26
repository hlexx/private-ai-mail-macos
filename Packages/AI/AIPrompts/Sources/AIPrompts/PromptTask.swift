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
    static func objectCandidates(from raw: String) -> [String] {
        let text = normalized(raw)
        let candidates = balancedObjectCandidates(in: text)
        return candidates.isEmpty ? [text] : candidates
    }

    static func seededPlainTextFallback(from raw: String) -> String? {
        let text = normalized(raw)
        guard balancedObjectCandidates(in: text).isEmpty else { return nil }
        guard text.first == "{" else { return nil }

        let body = String(text.dropFirst())
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !body.isEmpty else { return nil }
        guard !looksLikeJSONFragment(body) else { return nil }
        return body
    }

    static func firstStringValue(in raw: String, forKeys keys: [String]) -> String? {
        let text = normalized(raw)
        for key in keys {
            guard let keyRange = text.range(of: #""\#(key)""#),
                  let colon = text[keyRange.upperBound...].firstIndex(of: ":"),
                  let quote = text[text.index(after: colon)...].firstIndex(of: "\""),
                  let value = quotedString(in: text, startingAt: quote) else {
                continue
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func balancedObjectCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        var seen: Set<String> = []

        for start in text.indices where text[start] == "{" {
            guard let end = matchingObjectEnd(in: text, from: start) else { continue }
            let candidate = String(text[start...end])
            if seen.insert(candidate).inserted {
                candidates.append(candidate)
            }
        }

        return candidates
    }

    private static func normalized(_ raw: String) -> String {
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
        return text
    }

    private static func matchingObjectEnd(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false

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
                    return i
                }
            }
        }

        return nil
    }

    private static func looksLikeJSONFragment(_ text: String) -> Bool {
        text.contains("\":") || text.hasPrefix("\"") || text.hasPrefix("[")
    }

    private static func quotedString(in text: String, startingAt quote: String.Index) -> String? {
        var escaped = false
        var value = ""
        var index = text.index(after: quote)

        while index < text.endIndex {
            let ch = text[index]
            if escaped {
                value.append(ch)
                escaped = false
            } else if ch == "\\" {
                value.append(ch)
                escaped = true
            } else if ch == "\"" {
                return decodeJSONStringLiteral("\"\(value)\"") ?? value
            } else {
                value.append(ch)
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func decodeJSONStringLiteral(_ literal: String) -> String? {
        try? JSONDecoder().decode(String.self, from: Data(literal.utf8))
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}
