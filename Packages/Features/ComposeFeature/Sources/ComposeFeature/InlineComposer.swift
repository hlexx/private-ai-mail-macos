import AIKit
import DesignSystem
import SwiftUI

// MARK: - InlineComposer

// swiftlint:disable:next type_body_length
public struct InlineComposer: View {
    @AppStorage("pam.defaultTone") private var defaultToneRaw: String = "warm"
    @AppStorage("pam.preferredLanguage") var preferredLanguage: String = ""
    @State var tone: AIReplyTone
    @State var draftText: String = ""
    @State var detectedLanguage: String?
    @State var languageOverride: String?
    @State var draftGenerationRequested = false
    @State var showLanguagePicker = false
    @FocusState var isEditorFocused: Bool

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

    var effectiveLanguage: String? {
        languageOverride ?? replyLanguage
    }

    var effectiveLocale: Locale {
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
        .task(id: displayIdentity) {
            prepareDraftDisplay()
        }
        .onChange(of: replyStore.reply) { _, newReply in
            if let newReply, ReplyStore.isDisplayableDraft(newReply.body) {
                draftText = newReply.body
                detectedLanguage = newReply.detectedReplyLanguage
                draftGenerationRequested = true
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
                handleToneChange(newTone)
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
                        handleLanguageSelection(lang.code)
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

            if showsReadyState {
                draftReadyState
            }
        }
    }

    private var showsReadyState: Bool {
        !draftGenerationRequested
            && !replyStore.isLoading
            && replyStore.error == nil
            && !ReplyStore.isDisplayableDraft(draftText)
    }

    private var draftReadyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.rbAccent)

            VStack(spacing: 4) {
                Text(String(localized: "composer.ready.title", defaultValue: "Generate a local draft"))
                    .font(.rbGeist(14, weight: .semibold))
                    .foregroundStyle(Color.rbFg1)

                Text(String(
                    localized: "composer.ready.description",
                    defaultValue: "Reply text is created only after you ask for it."
                ))
                .font(.rbGeist(12))
                .foregroundStyle(Color.rbFg3)
                .multilineTextAlignment(.center)
            }

            Button {
                requestDraftGeneration(force: false)
            } label: {
                Label(String(localized: "composer.ready.generate", defaultValue: "Generate draft"), systemImage: "sparkle")
            }
            .buttonStyle(.rbPrimary)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgElev1)
    }

    private var draftErrorState: some View {
        VStack(spacing: 12) {
            Text(String(localized: "composer.error.title", defaultValue: "Draft generation failed"))
                .font(.rbGeist(14, weight: .semibold))
                .foregroundStyle(Color.rbFg2)

            Button {
                draftGenerationRequested = true
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

    private var displayIdentity: String {
        "\(threadID)_\(accountId ?? "")_\(replyLanguage ?? "")"
    }
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
