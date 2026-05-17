import DesignSystem
import SwiftUI
@preconcurrency import Translation

public struct TranslationToggleView: View {
    @Bindable var store: TranslationStore
    let detectedLanguage: String?
    let preferredLanguage: String
    let autoTranslate: Bool
    let messages: [(id: String, text: String)]

    @State private var translationConfig: TranslationSession.Configuration?

    public init(
        store: TranslationStore,
        detectedLanguage: String?,
        preferredLanguage: String,
        autoTranslate: Bool = false,
        messages: [(id: String, text: String)]
    ) {
        self.store = store
        self.detectedLanguage = detectedLanguage
        self.preferredLanguage = preferredLanguage
        self.autoTranslate = autoTranslate
        self.messages = messages
    }

    private var effectivePreferredLanguage: String {
        if preferredLanguage.isEmpty {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        return preferredLanguage
    }

    private var shouldShow: Bool {
        guard let detected = detectedLanguage else { return false }
        return detected != effectivePreferredLanguage
    }

    public var body: some View {
        if shouldShow {
            HStack(spacing: RBSpace.s2) {
                segmentedControl
                if store.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .translationTask(translationConfig) { session in
                await translateAll(session: session)
            }
            .onAppear {
                if autoTranslate && !store.showTranslated {
                    triggerTranslation()
                }
            }
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            segmentButton(
                title: String(localized: "translation.original", defaultValue: "Original"),
                isSelected: !store.showTranslated
            ) {
                store.showTranslated = false
            }
            segmentButton(
                title: String(localized: "translation.translated", defaultValue: "Translated"),
                isSelected: store.showTranslated
            ) {
                triggerTranslation()
            }
        }
        .padding(2)
        .background(Color.rbBgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.sm)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
    }

    private func segmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.rbGeist(12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.rbFg1 : Color.rbFg3)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(isSelected ? Color.rbAccentSoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.xs))
        }
        .buttonStyle(.plain)
    }

    private func triggerTranslation() {
        store.showTranslated = true

        let allCached = messages.allSatisfy { store.translatedText(for: $0.id) != nil }
        if allCached { return }

        guard let detected = detectedLanguage else { return }

        let source = Locale.Language(identifier: detected)
        let target = Locale.Language(identifier: effectivePreferredLanguage)

        if translationConfig == nil {
            translationConfig = TranslationSession.Configuration(source: source, target: target)
        } else {
            translationConfig?.invalidate()
            translationConfig = TranslationSession.Configuration(source: source, target: target)
        }
    }

    @MainActor
    private func translateAll(session: TranslationSession) async {
        store.setTranslating(true)
        defer { store.setTranslating(false) }

        // Collect pending message ids and texts
        var pending: [(id: String, text: String)] = []
        for msg in messages where store.translatedText(for: msg.id) == nil {
            pending.append((msg.id, msg.text))
        }
        guard !pending.isEmpty else { return }

        do {
            // Use the batch API via sequence to translate all at once.
            // The .translationTask closure runs on the main actor; session
            // methods are nonisolated but accept sending parameters.
            for item in pending {
                let translated = try await session.translate(item.text)
                store.setTranslation(for: item.id, text: translated.targetText)
            }
        } catch {
            store.setError(error)
        }
    }
}
