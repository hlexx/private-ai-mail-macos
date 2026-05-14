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
        You are an email analyst. Read the thread and output ONLY a JSON object matching the schema below. \
        Never invent senders, dates, or amounts. Leave fields as null when the source does not support a \
        confident value. confidence is your self-estimate between 0 and 1.
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
