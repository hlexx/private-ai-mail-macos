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

public enum ThreadBriefPrompt {

    public static let systemPrompt: String = """
        You are an email analyst. Output ONLY a JSON object — no text before or after. \
        Fields: summary (string), request (string or null), deadline (string or null), risk (string or null), \
        nextStep (string or null), evidence (array of short quotes), confidence (number 0-1). \
        Rules: never invent facts; use null when unsure; evidence must be verbatim quotes; keep response under 200 tokens. \
        Example output: {"summary":"Team sync on Q3 goals","request":"Review the deck by Friday","deadline":"Friday", \
        "risk":null,"nextStep":"Reply with feedback","evidence":["Review the deck by Friday","Q3 goals"],"confidence":0.9}
        """

    public static func taskPrompt(
        messages: [PromptMessage],
        attachments: [PromptAttachment]
    ) -> String {
        var parts: [String] = []

        parts.append("## Thread")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for msg in messages {
            let ts = formatter.string(from: msg.sentAt)
            parts.append("""
                [From: \(msg.from) | \(ts)]
                \(msg.bodyText)
                """)
        }

        if !attachments.isEmpty {
            parts.append("")
            parts.append("## Attachments")
            for att in attachments {
                let pages = att.pageCount.map { " (\($0) pages)" } ?? ""
                parts.append("- \(att.filename) [\(att.mime)]\(pages)")
            }
        }

        parts.append("")
        parts.append("## Output Schema")
        parts.append(ThreadBriefSchema.jsonSchemaString)
        parts.append("")
        parts.append("Reply with the JSON object only.")

        return parts.joined(separator: "\n")
    }
}
