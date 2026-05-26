import Foundation

// MARK: - Prompt Input

/// Lightweight data carrier for thread brief prompt rendering.
/// Mirrors AIKit.AIThreadInput without introducing a cross-package dependency.
public struct PromptMessage: Sendable {
    public let from: String
    public let sentAt: Date
    public let bodyText: String

    public init(from: String, sentAt: Date, bodyText: String) {
        self.from = from
        self.sentAt = sentAt
        self.bodyText = bodyText
    }
}

public struct PromptAttachment: Sendable {
    public let filename: String
    public let mime: String
    public let pageCount: Int?

    public init(filename: String, mime: String, pageCount: Int? = nil) {
        self.filename = filename
        self.mime = mime
        self.pageCount = pageCount
    }
}

// MARK: - Thread Brief Prompt

public struct ThreadBriefTaskInput: Sendable {
    public let messages: [PromptMessage]
    public let attachments: [PromptAttachment]

    public init(messages: [PromptMessage], attachments: [PromptAttachment]) {
        self.messages = messages
        self.attachments = attachments
    }
}

public enum ThreadBriefTask: PromptTaskDefinition {
    public typealias Input = ThreadBriefTaskInput
    public typealias Output = ParsedThreadBrief

    public static let metadata = PromptTaskMetadata(
        id: .threadBrief,
        promptVersion: "thread-brief.v2",
        schemaVersion: "thread-brief.schema.v1",
        modelProfile: "local-gemma-structured-json",
        maxInputCharacters: 6_000,
        maxOutputTokens: 512,
        examples: [
            #"{"summary":"Team sync on Q3 goals","request":"Review the deck by Friday","deadline":"Friday","risk":null,"nextStep":"Reply with feedback","evidence":["Review the deck by Friday","Q3 goals"],"confidence":0.9}"#,
        ],
        privacyCategory: "local-email-thread"
    )

    public static let systemPrompt: String = """
        You are an email analyst. Output ONLY a JSON object — no text before or after. \
        Fields: summary (string), request (string or null), deadline (string or null), risk (string or null), \
        nextStep (string or null), evidence (array of short quotes), confidence (number 0-1). \
        Rules: never invent facts; use null when unsure; evidence must be verbatim quotes; keep response under 200 tokens; \
        never copy schema words, placeholders, or examples as brief content.
        """

    public static let outputSeed = #"{"summary":"#

    public static let jsonSchemaString = ThreadBriefSchema.jsonSchemaString

    public static func renderUserPrompt(_ input: ThreadBriefTaskInput) -> String {
        var parts: [String] = []

        parts.append("## Thread")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for msg in input.messages {
            let ts = formatter.string(from: msg.sentAt)
            let body = PromptTextBudget.trimmedMessageBody(
                msg.bodyText,
                maxCharacters: metadata.maxInputCharacters
            )
            parts.append("""
                [From: \(msg.from) | \(ts)]
                \(body)
                """)
        }

        if !input.attachments.isEmpty {
            parts.append("")
            parts.append("## Attachments")
            for att in input.attachments {
                let pages = att.pageCount.map { " (\($0) pages)" } ?? ""
                parts.append("- \(att.filename) [\(att.mime)]\(pages)")
            }
        }

        parts.append("")
        parts.append("## Output JSON")
        parts.append("Keys: summary, request, deadline, risk, nextStep, evidence, confidence.")
        parts.append("Use null for unknown request, deadline, risk, and nextStep.")
        parts.append("Continue the seeded JSON object with the actual thread summary.")
        parts.append("")
        parts.append("Reply with JSON only. Do not output schema words or placeholders.")

        return parts.joined(separator: "\n")
    }

    public static func parse(_ rawOutput: String) throws -> ParsedThreadBrief {
        try ThreadBriefParser.parse(rawOutput)
    }
}

public enum ThreadBriefPrompt {
    public static let systemPrompt = ThreadBriefTask.systemPrompt

    public static func taskPrompt(
        messages: [PromptMessage],
        attachments: [PromptAttachment]
    ) -> String {
        ThreadBriefTask.renderUserPrompt(
            ThreadBriefTaskInput(messages: messages, attachments: attachments)
        )
    }
}
