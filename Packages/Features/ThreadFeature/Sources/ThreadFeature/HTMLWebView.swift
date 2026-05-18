import SwiftUI
import WebKit

/// NSViewRepresentable wrapper around WKWebView for rendering HTML email bodies.
/// JavaScript is disabled. Remote resource loading is blocked by default via CSP
/// and navigation policy; flip `allowRemoteImages` to permit remote `<img>` loads.
struct HTMLWebView: NSViewRepresentable {
    let html: String
    let attachments: [AttachmentData]
    let allowRemoteImages: Bool
    @Binding var contentHeight: CGFloat

    struct AttachmentData {
        let contentId: String
        let mime: String
        let data: Data
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let processed = resolvedHTML()

        guard processed != coordinator.lastHTML || allowRemoteImages != coordinator.lastAllowRemote else { return }
        coordinator.lastHTML = processed
        coordinator.lastAllowRemote = allowRemoteImages
        coordinator.heightBinding = $contentHeight

        webView.loadHTMLString(wrapHTML(processed), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - HTML Processing

    /// Replace cid: references with inline data: URLs from attachments.
    private func resolvedHTML() -> String {
        Self.resolveCIDReferences(in: html, attachments: attachments)
    }

    /// Testable CID resolution: replaces `cid:` references with inline `data:` URLs.
    static func resolveCIDReferences(in html: String, attachments: [AttachmentData]) -> String {
        var result = html
        for att in attachments {
            let dataURL = "data:\(att.mime);base64,\(att.data.base64EncodedString())"
            result = result.replacingOccurrences(of: "cid:\(att.contentId)", with: dataURL, options: .caseInsensitive)
            result = result.replacingOccurrences(of: "cid:<\(att.contentId)>", with: dataURL, options: .caseInsensitive)
        }
        return result
    }

    /// Strip injected `<meta http-equiv=...>`, `<base>`, and `</head>` / `<head>` tags
    /// from email body to prevent CSP override and URL redirection via HTML injection.
    private func sanitizeBody(_ body: String) -> String {
        var result = body
        // Remove any <meta http-equiv=...> tags that could override our CSP
        let metaPattern = #"<meta\s+[^>]*http-equiv\s*=[^>]*>"#
        result = result.replacingOccurrences(of: metaPattern, with: "", options: [.regularExpression, .caseInsensitive])
        // Remove <base> tags that could redirect relative URLs to an attacker domain
        let basePattern = #"<base\s[^>]*>"#
        result = result.replacingOccurrences(of: basePattern, with: "", options: [.regularExpression, .caseInsensitive])
        // Remove </head> and <head> tags that could break out of the body
        let headPattern = #"</?head\s*>"#
        result = result.replacingOccurrences(of: headPattern, with: "", options: [.regularExpression, .caseInsensitive])
        // Remove <html>, </html>, <body>, </body> to prevent template structure escape
        let htmlBodyPattern = #"</?(?:html|body)\s*[^>]*>"#
        result = result.replacingOccurrences(of: htmlBodyPattern, with: "", options: [.regularExpression, .caseInsensitive])
        return result
    }

    private func wrapHTML(_ body: String) -> String {
        let sanitized = sanitizeBody(body)
        let imgSrc = allowRemoteImages ? "img-src * cid: data: blob:;" : "img-src cid: data:;"
        let csp = "default-src 'none'; \(imgSrc) style-src 'unsafe-inline'; font-src data:;"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            font-size: 14px;
            line-height: 1.5;
            color: #e0e0e0;
            background: transparent;
            margin: 0;
            padding: 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        @media (prefers-color-scheme: light) {
            body { color: #1a1a1a; }
        }
        img { max-width: 100%; height: auto; }
        a { color: #5b9bd5; }
        pre, code { white-space: pre-wrap; word-wrap: break-word; }
        table { max-width: 100%; border-collapse: collapse; }
        td, th { word-wrap: break-word; }
        </style>
        </head>
        <body>
        \(sanitized)
        </body>
        </html>
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastAllowRemote: Bool = false
        var heightBinding: Binding<CGFloat>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let height = result as? Double {
                    Task { @MainActor in
                        self?.heightBinding?.wrappedValue = min(CGFloat(height), 2000)
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // Allow the initial loadHTMLString, block all other navigations (link clicks etc.)
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                // Open external links in the default browser
                if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            }
        }
    }
}
