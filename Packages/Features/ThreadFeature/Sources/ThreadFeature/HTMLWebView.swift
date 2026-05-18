import SwiftUI
import WebKit

/// A text node extracted from the HTML DOM for translation.
public struct TranslationTextNode: Sendable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// NSViewRepresentable wrapper around WKWebView for rendering HTML email bodies.
/// JavaScript is disabled. Remote resource loading is blocked by default via CSP
/// and navigation policy; flip `allowRemoteImages` to permit remote `<img>` loads.
struct HTMLWebView: NSViewRepresentable {
    let html: String
    let attachments: [AttachmentData]
    let allowRemoteImages: Bool
    @Binding var contentHeight: CGFloat
    var translatedNodes: [String: String]?
    var onTextNodesExtracted: (([TranslationTextNode]) -> Void)?

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

        let needsReload = processed != coordinator.lastHTML || allowRemoteImages != coordinator.lastAllowRemote
        let translationsChanged = translatedNodes != coordinator.lastTranslatedNodes

        if needsReload {
            coordinator.lastHTML = processed
            coordinator.lastAllowRemote = allowRemoteImages
            coordinator.heightBinding = $contentHeight
            coordinator.onTextNodesExtracted = onTextNodesExtracted
            coordinator.pendingTranslations = translatedNodes
            coordinator.lastTranslatedNodes = translatedNodes
            coordinator.hasExtracted = false
            webView.loadHTMLString(wrapHTML(processed), baseURL: nil)
        } else if translationsChanged {
            coordinator.lastTranslatedNodes = translatedNodes
            if let nodes = translatedNodes, !nodes.isEmpty {
                coordinator.applyTranslations(nodes, in: webView)
            } else if translatedNodes == nil && coordinator.hasExtracted {
                coordinator.restoreOriginals(in: webView)
            }
        }
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
        let headPattern = #"</?head\s*[^>]*>"#
        result = result.replacingOccurrences(of: headPattern, with: "", options: [.regularExpression, .caseInsensitive])
        // Remove <html>, </html>, <body>, </body> to prevent template structure escape
        let htmlBodyPattern = #"</?(?:html|body)\s*[^>]*>"#
        result = result.replacingOccurrences(of: htmlBodyPattern, with: "", options: [.regularExpression, .caseInsensitive])
        return result
    }

    private func wrapHTML(_ body: String) -> String {
        let sanitized = sanitizeBody(body)
        let imgSrc = allowRemoteImages ? "img-src * cid: data: blob:;" : "img-src cid: data:;"
        let csp = "default-src 'none'; \(imgSrc) style-src 'unsafe-inline'; font-src data:; frame-src 'none'; form-action 'none';"
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

    // MARK: - JavaScript for DOM-walk Translation

    static let extractionJS = """
    (function () {
        var out = [];
        var nodes = [];
        var w = document.createTreeWalker(
            document.body, NodeFilter.SHOW_TEXT,
            { acceptNode: function(n) {
                if (!n.parentNode) return NodeFilter.FILTER_REJECT;
                var tag = n.parentNode.nodeName;
                if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') return NodeFilter.FILTER_REJECT;
                if (n.nodeValue.trim().length === 0) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            }}
        );
        while (w.nextNode()) {
            nodes.push(w.currentNode);
            if (nodes.length >= 2000) break;
        }
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            var span = document.createElement('span');
            span.dataset.txId = 'n' + i;
            span.dataset.txOrig = node.nodeValue;
            span.textContent = node.nodeValue;
            node.parentNode.replaceChild(span, node);
            out.push({id: 'n' + i, text: span.textContent});
        }
        return JSON.stringify(out);
    })();
    """

    static func applyTranslationsJS(map: [String: String]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: map),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        return """
        (function () {
            var map = \(jsonString);
            var spans = document.querySelectorAll('[data-tx-id]');
            for (var i = 0; i < spans.length; i++) {
                var span = spans[i];
                var id = span.dataset.txId;
                if (map[id] !== undefined) span.textContent = map[id];
            }
        })();
        """
    }

    static let restoreOriginalsJS = """
    (function () {
        var spans = document.querySelectorAll('[data-tx-id]');
        for (var i = 0; i < spans.length; i++) {
            var span = spans[i];
            span.textContent = span.dataset.txOrig;
        }
    })();
    """

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastAllowRemote: Bool = false
        var heightBinding: Binding<CGFloat>?
        var onTextNodesExtracted: (([TranslationTextNode]) -> Void)?
        var pendingTranslations: [String: String]?
        var lastTranslatedNodes: [String: String]?
        var hasExtracted = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Measure height
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let height = result as? Double {
                    Task { @MainActor in
                        self?.heightBinding?.wrappedValue = min(CGFloat(height), 2000)
                    }
                }
            }

            // Extract text nodes if callback is set (guard against double-firing)
            if onTextNodesExtracted != nil && !hasExtracted {
                webView.evaluateJavaScript(HTMLWebView.extractionJS) { [weak self, weak webView] result, _ in
                    guard let self, let jsonString = result as? String else { return }
                    self.hasExtracted = true
                    guard let data = jsonString.data(using: .utf8),
                          let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
                    let nodes = array.compactMap { dict -> TranslationTextNode? in
                        guard let id = dict["id"], let text = dict["text"] else { return nil }
                        return TranslationTextNode(id: id, text: text)
                    }
                    Task { @MainActor [weak self, weak webView] in
                        self?.onTextNodesExtracted?(nodes)
                        // Apply pending translations if available
                        if let webView, let pending = self?.pendingTranslations, !pending.isEmpty {
                            self?.applyTranslations(pending, in: webView)
                            self?.pendingTranslations = nil
                        }
                    }
                }
            }
        }

        func applyTranslations(_ map: [String: String], in webView: WKWebView) {
            let js = HTMLWebView.applyTranslationsJS(map: map)
            guard !js.isEmpty else { return }
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func restoreOriginals(in webView: WKWebView) {
            webView.evaluateJavaScript(HTMLWebView.restoreOriginalsJS, completionHandler: nil)
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
