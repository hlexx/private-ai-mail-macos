import DesignSystem
import SwiftUI
@preconcurrency import Translation

public struct TranslationToggleView: View {
    @Bindable var store: TranslationStore
    let detectedLanguage: String?
    let preferredLanguage: String
    let autoTranslate: Bool
    let messages: [(id: String, text: String)]
    let htmlMessageIds: Set<String>

    @State private var translationConfig: TranslationSession.Configuration?

    private var messageFingerprint: String {
        messages.map(\.id).joined(separator: ",")
    }

    public init(
        store: TranslationStore,
        detectedLanguage: String?,
        preferredLanguage: String,
        autoTranslate: Bool = false,
        messages: [(id: String, text: String)],
        htmlMessageIds: Set<String> = []
    ) {
        self.store = store
        self.detectedLanguage = detectedLanguage
        self.preferredLanguage = preferredLanguage
        self.autoTranslate = autoTranslate
        self.messages = messages
        self.htmlMessageIds = htmlMessageIds
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
            .onChange(of: messageFingerprint) { _, _ in
                if autoTranslate && !store.showTranslated {
                    triggerTranslation()
                }
            }
            .onChange(of: store.needsRetranslation) { _, needs in
                if needs && store.showTranslated {
                    store.needsRetranslation = false
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

        // Check if all messages are cached (either as text or nodes)
        let allCached = messages.allSatisfy { msg in
            if htmlMessageIds.contains(msg.id) {
                return store.nodeTranslations(for: msg.id) != nil
            }
            return store.translatedText(for: msg.id) != nil
        }
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

        do {
            // Translate plain-text-only messages (no HTML body)
            for msg in messages where !htmlMessageIds.contains(msg.id) {
                guard store.translatedText(for: msg.id) == nil else { continue }
                let translated = try await session.translate(msg.text)
                store.setTranslation(for: msg.id, text: translated.targetText)
            }

            // For HTML messages, translate extracted nodes from the store
            for msgId in htmlMessageIds {
                guard store.nodeTranslations(for: msgId) == nil else { continue }
                guard let nodes = store.extractedNodes[msgId], !nodes.isEmpty else { continue }
                let generation = store.currentGeneration(for: msgId)

                var result: [String: String] = [:]
                for node in nodes {
                    guard store.currentGeneration(for: msgId) == generation else { break }
                    let translated = try await session.translate(node.text)
                    result[node.id] = translated.targetText
                }
                guard store.currentGeneration(for: msgId) == generation else { continue }
                store.setNodeTranslations(for: msgId, nodes: result)
            }
        } catch {
            store.setError(error)
            store.showTranslated = false
        }
    }
}
