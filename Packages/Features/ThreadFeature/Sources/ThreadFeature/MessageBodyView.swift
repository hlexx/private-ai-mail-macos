import AppKit
import DesignSystem
import Persistence
import SwiftUI

/// Renders a single email message body: HTML if available, otherwise plain text, else snippet.
/// Remote images are blocked by default; a pill appears when the message contains remote `<img>` tags.
struct MessageBodyView: View {
    let bodyHtml: String?
    let bodyText: String?
    let snippet: String
    let attachments: [HTMLWebView.AttachmentData]
    var translatedNodes: [String: String]?
    var onTextNodesExtracted: (([TranslationTextNode]) -> Void)?
    @State private var allowRemoteImages = false
    @State private var webViewHeight: CGFloat = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let html = bodyHtml, !html.isEmpty {
                if hasRemoteImages(html) {
                    remoteImagesPill
                }
                HTMLWebView(
                    html: html,
                    attachments: attachments,
                    allowRemoteImages: allowRemoteImages,
                    contentHeight: $webViewHeight,
                    translatedNodes: translatedNodes,
                    onTextNodesExtracted: onTextNodesExtracted
                )
                .frame(height: min(webViewHeight, 2000))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let text = bodyText, !text.isEmpty {
                Text(text)
                    .font(.rbGeist(14))
                    .foregroundStyle(Color.rbFg2)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            } else {
                Text(snippet)
                    .font(.rbGeist(14))
                    .foregroundStyle(Color.rbFg3)
                    .italic()
                    .textSelection(.enabled)
            }
        }
    }

    private var remoteImagesPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 11))
            Text(allowRemoteImages
                 ? String(localized: "thread.body.imagesLoaded", defaultValue: "Remote images loaded")
                 : String(localized: "thread.body.imagesBlocked", defaultValue: "Remote images blocked"))
                .font(.rbMono(11))
            if !allowRemoteImages {
                Text("\u{00B7}")
                Button(String(localized: "thread.body.showImages", defaultValue: "Show images")) {
                    allowRemoteImages = true
                }
                .buttonStyle(.plain)
                .font(.rbMono(11, weight: .semibold))
                .foregroundStyle(Color.rbAccentSoft)
            }
        }
        .foregroundStyle(Color.rbFg3)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.rbBgElev2)
        .clipShape(Capsule())
    }

    private func hasRemoteImages(_ html: String) -> Bool {
        // Check for <img src="http..."> or <img src="//..."> patterns
        let pattern = #"<img[^>]+src\s*=\s*["'](https?://|//)"#
        return html.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Plain text extraction from HTML

extension MessageBodyView {
    /// Convert HTML to plain text using NSAttributedString. Used by AI input pipeline.
    /// Must run on main thread (NSAttributedString with .html requires it).
    @MainActor static func htmlToPlainText(_ html: String) -> String? {
        let stripped = HTMLSanitizer.stripStyleAndScript(html)
        guard let data = stripped.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        var text = attributed.string
        // Strip excessive blank lines
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
