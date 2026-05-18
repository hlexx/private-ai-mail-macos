import Foundation
import GRDB

public struct MessageRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "message"

    public static let read = 1 << 1
    public static let sentByMe = 1 << 2

    public var id: String
    public var threadId: String
    public var accountId: String
    public var messageIdHeader: String?
    public var fromAddr: String?
    public var toAddr: String?
    public var ccAddr: String?
    public var sentAt: Int
    public var snippet: String?
    public var bodyHtml: String?
    public var bodyText: String?
    public var translatedText: String?
    public var flags: Int

    public init(id: String, threadId: String, accountId: String, messageIdHeader: String? = nil, fromAddr: String? = nil, toAddr: String? = nil, ccAddr: String? = nil, sentAt: Int, snippet: String? = nil, bodyHtml: String? = nil, bodyText: String? = nil, translatedText: String? = nil, flags: Int = 0) {
        self.id = id
        self.threadId = threadId
        self.accountId = accountId
        self.messageIdHeader = messageIdHeader
        self.fromAddr = fromAddr
        self.toAddr = toAddr
        self.ccAddr = ccAddr
        self.sentAt = sentAt
        self.snippet = snippet
        self.bodyHtml = bodyHtml
        self.bodyText = bodyText
        self.translatedText = translatedText
        self.flags = flags
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case accountId = "account_id"
        case messageIdHeader = "message_id_header"
        case fromAddr = "from_addr"
        case toAddr = "to_addr"
        case ccAddr = "cc_addr"
        case sentAt = "sent_at"
        case snippet
        case bodyHtml = "body_html"
        case bodyText = "body_text"
        case translatedText = "translated_text"
        case flags
    }

    /// Best-effort plain text: prefer bodyText, fall back to HTML-to-plain, then snippet.
    public var bestPlainText: String {
        if let text = bodyText, !text.isEmpty { return text }
        if let html = bodyHtml, !html.isEmpty {
            return Self.htmlToPlainText(html) ?? snippet ?? ""
        }
        return snippet ?? ""
    }

    /// Convert HTML to plain text by stripping tags. Thread-safe (no WebKit dependency).
    /// Used by BriefStore, BriefBackgroundQueue, and ReplyStore for AI input.
    /// MessageBodyView.htmlToPlainText uses NSAttributedString for higher fidelity UI display
    /// but requires MainActor — this regex variant is preferred for background/batch processing.
    public static func htmlToPlainText(_ html: String) -> String? {
        var text = HTMLSanitizer.stripStyleAndScript(html)
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
