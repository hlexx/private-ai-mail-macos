import DesignSystem
import SwiftUI

/// Standalone compose view with a focused desktop composer surface.
public struct ComposeWindowView: View {

    private let composerMaxWidth: CGFloat = 980

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
            composerSurface
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgCanvas)
        .onChange(of: richBody) { _, newValue in
            viewModel.bodyText = newValue.string
        }
        .onAppear {
            if richBody.string != viewModel.bodyText {
                let font = NSFont(name: "Geist-Regular", size: 14) ?? .systemFont(ofSize: 14)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle,
                ]
                richBody = NSAttributedString(string: viewModel.bodyText, attributes: attrs)
            }
        }
        .onChange(of: viewModel.sendState.key) { _, newKey in
            if newKey == "sent" {
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    dismiss()
                }
            }
        }
        .animation(RBEase.out(duration: RBDuration.d3), value: viewModel.sendState.key)
    }

    // MARK: - Head

    private var headSection: some View {
        HStack(spacing: RBSpace.s3) {
            VStack(alignment: .leading, spacing: RBSpace.s1) {
                Text(headerTitle)
                    .font(.rbGeist(18, weight: .semibold))
                    .foregroundStyle(Color.rbFg1)
                    .lineLimit(1)

                HStack(spacing: RBSpace.s2) {
                    if let selectedAccountEmail = viewModel.selectedAccountEmail,
                       !selectedAccountEmail.isEmpty {
                        ComposeIdentityPill(email: selectedAccountEmail)
                    }

                    ComposePrivacyPill()
                }
                .frame(minHeight: 24, alignment: .leading)
            }

            Spacer()

            RBIconButton(systemName: "xmark", accessibilityLabel: String(localized: "compose.close", defaultValue: "Close")) {
                dismiss()
            }
        }
        .frame(maxWidth: composerMaxWidth)
        .padding(.horizontal, RBSpace.s6)
        .padding(.top, RBSpace.s4)
        .padding(.bottom, RBSpace.s3)
    }

    private var headerTitle: String {
        viewModel.subjectField.isEmpty
            ? String(localized: "compose.newMessage", defaultValue: "New Message")
            : viewModel.subjectField
    }

    // MARK: - Surface

    private var composerSurface: some View {
        VStack(spacing: 0) {
            fieldRows
            Divider().overlay(Color.rbStroke1)
            editorSection
            Divider().overlay(Color.rbStroke1)
            approvalSection
            footerSection
        }
        .frame(maxWidth: composerMaxWidth, maxHeight: .infinity)
        .background(Color.rbBgDeep)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: RBRadius.lg)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 12)
        .padding(.horizontal, RBSpace.s6)
        .padding(.bottom, RBSpace.s6)
    }

    // MARK: - Field Rows

    private var fieldRows: some View {
        VStack(spacing: 0) {
            if viewModel.accounts.count > 1 {
                accountRow
                Divider().overlay(Color.rbStroke1)
            }
            fieldRow(
                label: String(localized: "compose.field.to", defaultValue: "To"),
                text: $viewModel.toField,
                placeholder: String(localized: "compose.field.toPlaceholder", defaultValue: "Add recipients")
            )
            Divider().overlay(Color.rbStroke1)
            fieldRow(
                label: String(localized: "compose.field.cc", defaultValue: "Cc"),
                text: $viewModel.ccField,
                placeholder: String(localized: "compose.field.ccPlaceholder", defaultValue: "Add cc recipients")
            )
            Divider().overlay(Color.rbStroke1)
            fieldRow(
                label: String(localized: "compose.field.subject", defaultValue: "Subject"),
                text: $viewModel.subjectField,
                placeholder: String(localized: "compose.field.subjectPlaceholder", defaultValue: "Add subject")
            )
        }
        .background(Color.rbBgDeep)
    }

    private func fieldRow(label: String, text: Binding<String>, placeholder: String? = nil) -> some View {
        HStack(spacing: RBSpace.s3) {
            Text(label)
                .font(.rbMono(11, weight: .medium))
                .foregroundStyle(Color.rbFg3)
                .lineLimit(1)
                .frame(width: 66, alignment: .leading)
            TextField(placeholder ?? "", text: text)
                .textFieldStyle(.plain)
                .font(.rbGeist(14))
                .foregroundStyle(Color.rbFg1)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, RBSpace.s5)
    }

    private var accountRow: some View {
        HStack(spacing: RBSpace.s3) {
            Text(String(localized: "compose.field.from", defaultValue: "From"))
                .font(.rbMono(11, weight: .medium))
                .foregroundStyle(Color.rbFg3)
                .lineLimit(1)
                .frame(width: 66, alignment: .leading)
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
        .frame(minHeight: 44)
        .padding(.horizontal, RBSpace.s5)
    }

    // MARK: - Editor

    private var editorSection: some View {
        ZStack(alignment: .topLeading) {
            RichTextEditor(attributedText: $richBody)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if richBody.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(String(localized: "compose.body.placeholder", defaultValue: "Write your message\u{2026}"))
                    .font(.rbGeist(14))
                    .foregroundStyle(Color.rbFg4)
                    .padding(.leading, RBSpace.s5)
                    .padding(.top, RBSpace.s5)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.rbBgDeep)
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
        HStack(spacing: RBSpace.s3) {
            Label(String(localized: "compose.footer.meta", defaultValue: "Drafted locally"), systemImage: "lock.fill")
                .font(.rbMono(11, weight: .medium))
                .foregroundStyle(Color.rbFg3)
                .lineLimit(1)

            HStack(spacing: RBSpace.s1) {
                ComposeFooterToolButton(
                    systemName: "paperclip",
                    label: String(localized: "compose.tool.attach", defaultValue: "Attach file")
                )
                ComposeFooterToolButton(
                    systemName: "textformat",
                    label: String(localized: "compose.tool.formatting", defaultValue: "Formatting")
                )
                ComposeFooterToolButton(
                    systemName: "sparkle",
                    label: String(localized: "compose.cta.rewrite", defaultValue: "Rewrite")
                )
            }

            Spacer()

            HStack(spacing: RBSpace.s2) {
                Button {
                } label: {
                    Label(String(localized: "compose.cta.saveDraft", defaultValue: "Save draft"), systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.rbGhost)
                .disabled(true)
                .help(String(localized: "compose.cta.saveDraft.help", defaultValue: "Draft saving is not available yet"))

                Button {
                    viewModel.requestSend()
                } label: {
                    Label(String(localized: "compose.cta.send", defaultValue: "Send"), systemImage: "paperplane.fill")
                }
                .buttonStyle(.rbPrimary)
                .disabled(!isSendEnabled)
                .keyboardShortcut(.return, modifiers: [.command])
                .help(String(localized: "compose.cta.send.help", defaultValue: "Send (\u{2318}\u{23CE})"))
            }
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
        .background(Color.rbBgDeep)
    }

    private var isSendEnabled: Bool {
        viewModel.canRequestSend
    }
}

private struct ComposeIdentityPill: View {
    let email: String

    var body: some View {
        Label(email, systemImage: "person.crop.circle")
            .font(.rbMono(11, weight: .medium))
            .foregroundStyle(Color.rbFg2)
            .lineLimit(1)
            .padding(.horizontal, RBSpace.s2)
            .padding(.vertical, RBSpace.s1)
            .background(Color.rbBgElev1)
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }
}

private struct ComposePrivacyPill: View {
    var body: some View {
        Label(String(localized: "compose.status.localDraft", defaultValue: "Local draft"), systemImage: "lock.fill")
            .font(.rbMono(11, weight: .medium))
            .foregroundStyle(Color.rbSignalLocalAi)
            .lineLimit(1)
            .padding(.horizontal, RBSpace.s2)
            .padding(.vertical, RBSpace.s1)
            .background(Color.rbSignalLocalAiBg)
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }
}

private struct ComposeFooterToolButton: View {
    let systemName: String
    let label: String

    var body: some View {
        Button {
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.rbFg3)
                .frame(width: 30, height: 30)
                .background(Color.rbBgElev1)
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .help("\(label) is not available yet")
        .opacity(0.72)
    }
}

#if DEBUG
#Preview("Compose Window") {
    ComposeWindowView(viewModel: {
        let vm = ComposeViewModel(composeServiceFactory: { _ in
            PreviewComposeService()
        })
        vm.toField = "marta@acme.de"
        vm.ccField = "legal@acme.de"
        vm.subjectField = "Re: Contract approval"
        vm.bodyText = "Hi Marta,\n\n"
        vm.selectedAccountID = "acc1"
        vm.selectedAccountEmail = "alex@example.com"
        return vm
    }())
    .frame(width: 860, height: 640)
    .preferredColorScheme(.light)
}

private struct PreviewComposeService: ComposeService {
    func send(_ draft: ComposeDraft) async throws -> SentEcho {
        SentEcho(messageID: "preview", threadID: "preview", sentAt: Date())
    }
}
#endif
