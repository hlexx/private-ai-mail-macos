import AIKit
import DesignSystem
import SwiftUI

// MARK: - InlineComposer

// swiftlint:disable:next type_body_length
public struct InlineComposer: View {
    @AppStorage("pam.defaultTone") private var defaultToneRaw: String = "warm"
    @AppStorage("pam.preferredLanguage") private var preferredLanguage: String = ""
    @State private var tone: AIReplyTone
    @State private var draftText: String = ""
    @State private var detectedLanguage: String?
    @State private var languageOverride: String?
    @State private var showLanguagePicker = false
    @FocusState private var isEditorFocused: Bool

    let threadID: String
    let accountId: String?
    let replyLanguage: String?
    let replyStore: ReplyStore
    let sendState: ComposeSendState
    let onEditInFull: (String) -> Void
    let onSend: (String) -> Void
    let onCancelSend: () -> Void
    let onRetrySend: () -> Void
    let onConfirmSendNow: () -> Void
    let onReauthorize: () -> Void

    public init(
        threadID: String,
        accountId: String? = nil,
        replyLanguage: String? = nil,
        replyStore: ReplyStore,
        sendState: ComposeSendState = .idle,
        onEditInFull: @escaping (String) -> Void = { _ in },
        onSend: @escaping (String) -> Void = { _ in },
        onCancelSend: @escaping () -> Void = {},
        onRetrySend: @escaping () -> Void = {},
        onConfirmSendNow: @escaping () -> Void = {},
        onReauthorize: @escaping () -> Void = {}
    ) {
        self.threadID = threadID
        self.accountId = accountId
        self.replyLanguage = replyLanguage
        self.replyStore = replyStore
        self.sendState = sendState
        self.onEditInFull = onEditInFull
        self.onSend = onSend
        self.onCancelSend = onCancelSend
        self.onRetrySend = onRetrySend
        self.onConfirmSendNow = onConfirmSendNow
        self.onReauthorize = onReauthorize
        // Read default tone synchronously so .task uses the correct value
        let raw = UserDefaults.standard.string(forKey: "pam.defaultTone") ?? "warm"
        _tone = State(initialValue: AIReplyTone(rawValue: raw) ?? .warm)
    }

    private var effectiveLanguage: String? {
        languageOverride ?? replyLanguage
    }

    private var effectiveLocale: Locale {
        preferredLanguage.isEmpty ? .current : Locale(identifier: preferredLanguage)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerRow
            textArea
            inlineSendStatus
            footerRow
        }
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.lg)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .padding(.top, 18)
        .task(id: "\(threadID)_\(effectiveLanguage ?? "")") {
            replyStore.generate(threadID: threadID, accountId: accountId, tone: tone, replyLanguage: effectiveLanguage, locale: effectiveLocale)
        }
        .onChange(of: replyStore.reply) { _, newReply in
            if let newReply, ReplyStore.isDisplayableDraft(newReply.body) {
                draftText = newReply.body
                detectedLanguage = newReply.detectedReplyLanguage
                isEditorFocused = true
            } else if newReply != nil {
                draftText = ""
            } else if replyStore.error != nil {
                draftText = ""
            }
        }
        .onChange(of: replyStore.focusRequestCount) { _, _ in
            if replyStore.reply != nil { isEditorFocused = true }
        }
        .onChange(of: replyStore.error != nil) { _, hasError in
            if hasError { draftText = "" }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            eyebrowLabel
            Spacer()
            RBToneSegment(
                segments: AIReplyTone.allCases.map { t in
                    RBToneSegment.Segment(
                        id: t,
                        label: t.rawValue.capitalized,
                        detail: ""
                    )
                },
                selection: $tone
            )
            .onChange(of: tone) { _, newTone in
                replyStore.generate(threadID: threadID, accountId: accountId, tone: newTone, replyLanguage: effectiveLanguage, locale: effectiveLocale)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }

    private var eyebrowLabel: some View {
        HStack(spacing: 4) {
            EyebrowLabel(eyebrowText)
            if displayLanguage != nil {
                languageChevron
            }
        }
    }

    private var displayLanguage: String? {
        detectedLanguage ?? effectiveLanguage
    }

    private var eyebrowText: String {
        var parts = [
            String(localized: "composer.eyebrow.draftReply", defaultValue: "Draft reply"),
            String(localized: "composer.eyebrow.local", defaultValue: "local")
        ]
        if let lang = displayLanguage {
            let prefix = String(localized: "composer.eyebrow.inLanguage", defaultValue: "in")
            parts.append("\(prefix) \(lang.uppercased())")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var languageChevron: some View {
        Button {
            showLanguagePicker.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.rbFg3)
        }
        .buttonStyle(.plain)
        .help(String(localized: "composer.languagePicker.tooltip", defaultValue: "Change reply language"))
        .popover(isPresented: $showLanguagePicker, arrowEdge: .bottom) {
            languagePickerContent
        }
    }

    private var languagePickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.commonLanguages, id: \.code) { lang in
                    Button {
                        languageOverride = lang.code
                        showLanguagePicker = false
                        replyStore.generate(threadID: threadID, accountId: accountId, tone: tone, replyLanguage: lang.code, locale: effectiveLocale)
                    } label: {
                        HStack {
                            Text(lang.name)
                                .font(.rbGeist(13))
                                .foregroundStyle(Color.rbFg1)
                            Spacer()
                            if (displayLanguage ?? "") == lang.code {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.rbAccent)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 200, height: 320)
    }

    // MARK: - Text Area

    private var textArea: some View {
        ZStack {
            TextEditor(text: $draftText)
                .focused($isEditorFocused)
                .font(.rbGeist(14))
                .foregroundStyle(Color.rbFg1)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(minHeight: 130, maxHeight: 260)
                .background(Color.rbBgElev1)
                .opacity(replyStore.isLoading ? 0.4 : 1.0)

            if replyStore.isLoading {
                Text(String(localized: "composer.loading", defaultValue: "Drafting\u{2026}"))
                    .font(.rbGeist(14))
                    .foregroundStyle(Color.rbFg3)
            }

            if replyStore.error != nil, !replyStore.isLoading {
                draftErrorState
            }
        }
    }

    private var draftErrorState: some View {
        VStack(spacing: 12) {
            Text(String(localized: "composer.error.title", defaultValue: "Draft generation failed"))
                .font(.rbGeist(14, weight: .semibold))
                .foregroundStyle(Color.rbFg2)

            Button {
                replyStore.regenerate(
                    threadID: threadID,
                    accountId: accountId,
                    tone: tone,
                    replyLanguage: effectiveLanguage,
                    locale: effectiveLocale
                )
            } label: {
                Text(String(localized: "composer.error.retry", defaultValue: "Retry"))
            }
            .buttonStyle(.rbSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgElev1)
    }

    // MARK: - Footer

    @ViewBuilder
    private var inlineSendStatus: some View {
        switch sendState {
        case .idle:
            EmptyView()
        case .awaitingApproval:
            statusStrip(
                icon: "paperplane.fill",
                text: String(localized: "composer.send.awaiting", defaultValue: "Ready to send"),
                primaryTitle: String(localized: "approval.sendNow", defaultValue: "Send now"),
                primaryAction: onConfirmSendNow,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .pending:
            statusStrip(
                icon: "tray.and.arrow.up.fill",
                text: String(localized: "composer.send.pending", defaultValue: "Queued locally"),
                primaryTitle: nil,
                primaryAction: nil,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .sending:
            statusStrip(
                icon: "paperplane.fill",
                text: String(localized: "approval.sending", defaultValue: "Sending\u{2026}"),
                primaryTitle: nil,
                primaryAction: nil,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .retrying:
            statusStrip(
                icon: "clock.arrow.circlepath",
                text: String(localized: "composer.send.retrying", defaultValue: "Retry scheduled"),
                primaryTitle: String(localized: "approval.retryNow", defaultValue: "Retry now"),
                primaryAction: onRetrySend,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .needsReconsent:
            statusStrip(
                icon: "person.badge.key.fill",
                text: ApprovalRow.errorMessage(.needsReconsent),
                primaryTitle: String(localized: "approval.reauthorize", defaultValue: "Re-authorize"),
                primaryAction: onReauthorize,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .sent:
            statusStrip(
                icon: "checkmark.circle.fill",
                text: String(localized: "approval.sent", defaultValue: "Sent"),
                primaryTitle: nil,
                primaryAction: nil,
                secondaryTitle: nil,
                secondaryAction: nil
            )
        case .failed(let error):
            statusStrip(
                icon: "exclamationmark.triangle.fill",
                text: ApprovalRow.errorMessage(error),
                primaryTitle: String(localized: "approval.retry", defaultValue: "Retry"),
                primaryAction: onRetrySend,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        }
    }

    private func statusStrip(
        icon: String,
        text: String,
        primaryTitle: String?,
        primaryAction: (() -> Void)?,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        HStack(spacing: RBSpace.s2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rbAccent)
            Text(text)
                .font(.rbGeist(12))
                .foregroundStyle(Color.rbFg2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: RBSpace.s2)
            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.rbPrimary)
                    .controlSize(.small)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.rbGhost)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.rbBgElev1)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }

    private var footerRow: some View {
        HStack {
            citationsLine
            Spacer()
            ctaButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.rbBgCanvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }

    private var citationsLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            if let reply = replyStore.reply, !reply.evidenceMessageIDs.isEmpty {
                Text("\(reply.evidenceMessageIDs.count) citations \u{00B7} \(reply.evidenceMessageIDs.joined(separator: " \u{00B7} "))")
            } else {
                Text("On-device AI")
            }
        }
        .font(.rbMono(10.5))
        .foregroundStyle(Color.rbFg3)
    }

    private var ctaButtons: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 400
            HStack(spacing: RBSpace.s2) {
                Spacer(minLength: 0)

                Button {
                    replyStore.regenerate(threadID: threadID, accountId: accountId, tone: tone, replyLanguage: effectiveLanguage, locale: effectiveLocale)
                } label: {
                    Label(String(localized: "composer.cta.regenerate", defaultValue: "Regenerate"), systemImage: "sparkle")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(.rbGhost)
                .fixedSize(horizontal: false, vertical: true)

                if narrow {
                    Button {
                        onEditInFull(draftText)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.rbSecondary)
                    .help(String(localized: "composer.cta.editInFull", defaultValue: "Edit in full"))
                    .disabled(!canSubmitDraft)
                } else {
                    Button {
                        onEditInFull(draftText)
                    } label: {
                        Text(String(localized: "composer.cta.editInFull", defaultValue: "Edit in full"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .buttonStyle(.rbSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(!canSubmitDraft)
                }

                Button {
                    onSend(draftText)
                } label: {
                    Label(String(localized: "composer.cta.send", defaultValue: "Send"), systemImage: "paperplane.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(.rbPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .disabled(!canSubmitDraft || !sendState.allowsNewSendRequest)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send (⌘⏎)")
            }
        }
        .frame(height: 32)
    }

    private var canSubmitDraft: Bool {
        !replyStore.isLoading
            && replyStore.error == nil
            && ReplyStore.isDisplayableDraft(draftText)
    }
}

extension InlineComposer {
    static let commonLanguages: [(code: String, name: String)] = [
        ("en", "English"), ("ru", "Русский"), ("de", "Deutsch"),
        ("fr", "Français"), ("es", "Español"), ("it", "Italiano"),
        ("pt", "Português"), ("zh", "中文"), ("ja", "日本語"),
        ("ko", "한국어"), ("ar", "العربية"), ("hi", "हिन्दी"),
        ("tr", "Türkçe"), ("pl", "Polski"), ("nl", "Nederlands"),
        ("uk", "Українська"), ("cs", "Čeština"), ("sv", "Svenska"),
        ("da", "Dansk"), ("fi", "Suomi"), ("no", "Norsk"),
        ("he", "עברית"), ("th", "ไทย"), ("vi", "Tiếng Việt"),
        ("id", "Bahasa Indonesia"), ("ms", "Bahasa Melayu"),
        ("ro", "Română"), ("hu", "Magyar"), ("el", "Ελληνικά"),
        ("bg", "Български"),
    ]
}

#if DEBUG
#Preview("Inline Composer") {
    InlineComposer(
        threadID: "preview-thread",
        replyStore: ReplyStore()
    )
    .padding(24)
    .background(Color.rbBgCanvas)
    .frame(width: 600)
    .preferredColorScheme(.dark)
}
#endif
