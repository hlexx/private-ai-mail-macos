import DesignSystem
import SwiftUI

/// Full-screen compose view matching the Composer.jsx design.
/// Renders header (subject + close), 3 field rows (to/cc/subj),
/// a RichTextEditor body, and footer with metadata + CTAs.
public struct ComposeWindowView: View {

    @Bindable var viewModel: ComposeViewModel
    @State private var richBody: NSAttributedString
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: ComposeViewModel) {
        self.viewModel = viewModel
        let font = NSFont(name: "Geist-Regular", size: 14) ?? .systemFont(ofSize: 14)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
        self._richBody = State(initialValue: NSAttributedString(string: viewModel.bodyText, attributes: attrs))
    }

    public var body: some View {
        VStack(spacing: 0) {
            headSection
            Divider().overlay(Color.rbStroke1)
            fieldRows
            Divider().overlay(Color.rbStroke1)
            editorSection
            Divider().overlay(Color.rbStroke1)
            approvalSection
            footerSection
        }
        .background(Color.rbBgCanvas)
        .onChange(of: richBody) { _, newValue in
            viewModel.bodyText = newValue.string
        }
        .onChange(of: viewModel.sendState.key) { _, newKey in
            if newKey == "sent" {
                dismiss()
            }
        }
        .animation(RBEase.out(duration: RBDuration.d3), value: viewModel.sendState.key)
    }

    // MARK: - Head

    private var headSection: some View {
        HStack {
            Text(viewModel.subjectField.isEmpty ? String(localized: "compose.newMessage", defaultValue: "New Message") : viewModel.subjectField)
                .rbTextStyle(.h3)
                .foregroundStyle(Color.rbFg1)
                .lineLimit(1)
            Spacer()
            RBIconButton(systemName: "xmark", accessibilityLabel: String(localized: "compose.close", defaultValue: "Close")) {
                dismiss()
            }
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s4)
    }

    // MARK: - Field Rows

    private var fieldRows: some View {
        VStack(spacing: 0) {
            fieldRow(label: String(localized: "compose.field.to", defaultValue: "to"), text: $viewModel.toField)
            Divider().overlay(Color.rbStroke1)
            fieldRow(label: String(localized: "compose.field.cc", defaultValue: "cc"), text: $viewModel.ccField, placeholder: String(localized: "compose.field.ccPlaceholder", defaultValue: "add recipient\u{2026}"))
            Divider().overlay(Color.rbStroke1)
            fieldRow(label: String(localized: "compose.field.subject", defaultValue: "subj"), text: $viewModel.subjectField)
            if viewModel.accounts.count > 1 {
                Divider().overlay(Color.rbStroke1)
                accountRow
            }
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

    private var accountRow: some View {
        HStack(spacing: RBSpace.s3) {
            Text(String(localized: "compose.field.from", defaultValue: "from"))
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg3)
                .frame(width: 32, alignment: .trailing)
            Picker("", selection: Binding(
                get: { viewModel.selectedAccountID ?? "" },
                set: { newID in
                    viewModel.selectedAccountID = newID
                    viewModel.selectedAccountEmail = viewModel.accounts.first(where: { $0.id == newID })?.email
                }
            )) {
                ForEach(viewModel.accounts) { account in
                    Text(account.email).tag(account.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer()
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
    }

    // MARK: - Editor

    private var editorSection: some View {
        RichTextEditor(attributedText: $richBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Approval

    @ViewBuilder
    private var approvalSection: some View {
        let isIdle: Bool = {
            if case .idle = viewModel.sendState { return true }
            return false
        }()
        if !isIdle {
            ApprovalRow(
                recipientCount: viewModel.recipientCount,
                accountEmail: viewModel.selectedAccountEmail ?? "",
                sendState: viewModel.sendState,
                onCancel: { viewModel.cancelSend() },
                onConfirmNow: { viewModel.confirmSendNow() },
                onRetrySend: { viewModel.retrySend() },
                onReauthorize: { viewModel.reauthorizeAndRetry() }
            )
            .padding(.horizontal, RBSpace.s3)
            .padding(.vertical, RBSpace.s2)
            Divider().overlay(Color.rbStroke1)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            EyebrowLabel(String(localized: "compose.footer.meta", defaultValue: "\u{25C6} drafted locally"))
            Spacer()
            HStack(spacing: RBSpace.s2) {
                Button(String(localized: "compose.cta.saveDraft", defaultValue: "Save draft")) {}
                    .buttonStyle(.rbGhost)

                Button {
                    // TODO(§15-step-4): replace with AIKit.rewrite()
                } label: {
                    Label(String(localized: "compose.cta.rewrite", defaultValue: "Rewrite"), systemImage: "sparkle")
                }
                .buttonStyle(.rbSecondary)

                Button {
                    viewModel.requestSend()
                } label: {
                    Label(String(localized: "compose.cta.send", defaultValue: "Send"), systemImage: "arrow.up")
                }
                .buttonStyle(.rbPrimary)
                .disabled(!isSendEnabled)
            }
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
    }

    private var isSendEnabled: Bool {
        if case .idle = viewModel.sendState {
            return !viewModel.toField.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return false
    }
}

#if DEBUG
#Preview("Compose Window") {
    ComposeWindowView(viewModel: {
        let vm = ComposeViewModel(composeServiceFactory: { _ in
            PreviewComposeService()
        })
        vm.toField = "marta@acme.de"
        vm.subjectField = "Re: Contract approval \u{2014} Acme GmbH"
        vm.bodyText = "Hi Marta — draft by Friday."
        return vm
    }())
    .frame(width: 700, height: 560)
    .preferredColorScheme(.dark)
}

private struct PreviewComposeService: ComposeService {
    func send(_ draft: ComposeDraft) async throws -> SentEcho {
        SentEcho(messageID: "preview", threadID: "preview", sentAt: Date())
    }
}
#endif
