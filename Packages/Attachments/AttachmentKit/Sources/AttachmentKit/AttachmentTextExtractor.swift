import Foundation
import PDFKit

public enum AttachmentTextExtractionStatus: String, Sendable, Codable {
    case extracted
    case unsupported
}

public struct AttachmentTextExtractionResult: Sendable, Equatable, Codable {
    public let status: AttachmentTextExtractionStatus
    public let text: String?
    public let unsupportedReason: String?
    public let extractionVersion: String

    public init(
        status: AttachmentTextExtractionStatus,
        text: String?,
        unsupportedReason: String?,
        extractionVersion: String = AttachmentTextExtractor.extractionVersion
    ) {
        self.status = status
        self.text = text
        self.unsupportedReason = unsupportedReason
        self.extractionVersion = extractionVersion
    }
}

public enum AttachmentTextExtractor {
    public static let extractionVersion = "attachment-text-extraction.v1"

    public static func extract(data: Data, mime: String, filename: String?) -> AttachmentTextExtractionResult {
        let normalizedMime = mime.lowercased()

        if normalizedMime == "application/pdf" || filename?.lowercased().hasSuffix(".pdf") == true {
            return extractPDF(data)
        }

        if normalizedMime == "text/html" || filename?.lowercased().hasSuffix(".html") == true {
            guard let html = String(data: data, encoding: .utf8) else {
                return unsupported("HTML attachment is not valid UTF-8")
            }
            return extracted(stripHTML(html))
        }

        if normalizedMime.hasPrefix("text/")
            || normalizedMime == "application/json"
            || normalizedMime == "text/csv"
            || filename?.lowercased().hasSuffix(".json") == true
            || filename?.lowercased().hasSuffix(".csv") == true {
            guard let text = String(data: data, encoding: .utf8) else {
                return unsupported("Text attachment is not valid UTF-8")
            }
            return extracted(text)
        }

        return unsupported("Unsupported attachment type: \(mime)")
    }

    private static func extractPDF(_ data: Data) -> AttachmentTextExtractionResult {
        guard let document = PDFDocument(data: data) else {
            return unsupported("PDF could not be opened")
        }
        var parts: [String] = []
        for index in 0..<document.pageCount {
            if let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                parts.append(text)
            }
        }
        let text = parts.joined(separator: "\n\n")
        guard !text.isEmpty else {
            return unsupported("PDF did not contain extractable text")
        }
        return extracted(text)
    }

    private static func extracted(_ text: String) -> AttachmentTextExtractionResult {
        AttachmentTextExtractionResult(status: .extracted, text: text, unsupportedReason: nil)
    }

    private static func unsupported(_ reason: String) -> AttachmentTextExtractionResult {
        AttachmentTextExtractionResult(status: .unsupported, text: nil, unsupportedReason: reason)
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "(?is)<(script|style).*?>.*?</\\1>",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
