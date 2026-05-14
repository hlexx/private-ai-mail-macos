import AppKit
import DesignSystem
import SwiftUI

/// NSViewRepresentable wrapping `NSTextView` for rich-text editing.
/// Supports bold/italic/links/quote-citation via standard NSAttributedString.
public struct RichTextEditor: NSViewRepresentable {
    @Binding public var attributedText: NSAttributedString

    public init(attributedText: Binding<NSAttributedString>) {
        self._attributedText = attributedText
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.font = NSFont(name: "Geist-Regular", size: 14) ?? .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false

        textView.typingAttributes = Self.defaultTypingAttributes

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        textView.textStorage?.setAttributedString(attributedText)

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !context.coordinator.isEditing,
           textView.textStorage?.string != attributedText.string {
            textView.textStorage?.setAttributedString(attributedText)
        }
    }

    static var defaultTypingAttributes: [NSAttributedString.Key: Any] {
        let font = NSFont(name: "Geist-Regular", size: 14) ?? .systemFont(ofSize: 14)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var isEditing = false

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        public func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        public func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }
            parent.attributedText = NSAttributedString(attributedString: storage)
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }
            parent.attributedText = NSAttributedString(attributedString: storage)
        }
    }
}
