import DesignSystem
import SwiftUI

/// Full-screen compose view matching the Composer.jsx design.
/// Renders header (subject + close), 3 field rows (to/cc/subj),
/// a RichTextEditor body, and footer with metadata + CTAs.
public struct ComposeWindowView: View {

    @State private var toField: String = "marta@acme.de"
    @State private var ccField: String = ""
    @State private var subjectField: String = "Re: Contract approval \u{2014} Acme GmbH"
    @State private var richBody: NSAttributedString

    let onClose: () -> Void

    // TODO(§15-step-4): replace stub with AIKit.draftReply(tone:)
    private static let defaultBody = "Hi Marta \u{2014} yes, I\u{2019}ll send a clean draft by Friday EOD. I\u{2019}ll match the pricing we agreed and flag the two clauses we discussed for your legal team.\n\nIf there\u{2019}s anything else you\u{2019}d like me to include \u{2014} SLA terms, payment schedule \u{2014} let me know.\n\n\u{2014} Alex"

    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        let font = NSFont(name: "Geist-Regular", size: 14) ?? .systemFont(ofSize: 14)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
        self._richBody = State(initialValue: NSAttributedString(string: Self.defaultBody, attributes: attrs))
    }

    public var body: some View {
        VStack(spacing: 0) {
            headSection
            Divider().overlay(Color.rbStroke1)
            fieldRows
            Divider().overlay(Color.rbStroke1)
            editorSection
            Divider().overlay(Color.rbStroke1)
            footerSection
        }
        .background(Color.rbBgCanvas)
    }

    // MARK: - Head

    private var headSection: some View {
        HStack {
            Text(subjectField)
                .rbTextStyle(.h3)
                .foregroundStyle(Color.rbFg1)
                .lineLimit(1)
            Spacer()
            RBIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                onClose()
            }
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s4)
    }

    // MARK: - Field Rows

    private var fieldRows: some View {
        VStack(spacing: 0) {
            fieldRow(label: "to", text: $toField)
            Divider().overlay(Color.rbStroke1)
            fieldRow(label: "cc", text: $ccField, placeholder: "add recipient\u{2026}")
            Divider().overlay(Color.rbStroke1)
            fieldRow(label: "subj", text: $subjectField)
        }
    }

    private func fieldRow(label: String, text: Binding<String>, placeholder: String? = nil) -> some View {
        HStack(spacing: RBSpace.s3) {
            Text(label)
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg3)
                .frame(width: 32, alignment: .trailing)
            TextField(placeholder ?? "", text: text)
                .textFieldStyle(.plain)
                .font(.rbGeist(14))
                .foregroundStyle(text.wrappedValue.isEmpty ? Color.rbFg3 : Color.rbFg1)
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
    }

    // MARK: - Editor

    private var editorSection: some View {
        RichTextEditor(attributedText: $richBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            EyebrowLabel("\u{25C6} drafted locally \u{00B7} attached contract.pdf \u{00B7} tone: concise")
            Spacer()
            HStack(spacing: RBSpace.s2) {
                Button("Save draft") {}
                    .buttonStyle(.rbGhost)

                Button {
                    // TODO(§15-step-4): replace with AIKit.rewrite()
                } label: {
                    Label("Rewrite", systemImage: "sparkle")
                }
                .buttonStyle(.rbSecondary)

                Button {
                    // TODO(§15-step-7): wire real send
                } label: {
                    Label("Send", systemImage: "arrow.up")
                }
                .buttonStyle(.rbPrimary)
            }
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
    }
}

#if DEBUG
#Preview("Compose Window") {
    ComposeWindowView()
        .frame(width: 700, height: 560)
        .preferredColorScheme(.dark)
}
#endif
