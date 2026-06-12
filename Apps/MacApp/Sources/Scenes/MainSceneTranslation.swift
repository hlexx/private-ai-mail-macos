import AppFoundation
import Foundation
import SwiftUI
import ThreadFeature
import TranslationFeature

// Owns app-shell translation preferences and language detection wiring. Keep
// translation execution, cache semantics, and package behavior in
// TranslationFeature.
struct MainSceneTranslationPreferenceState: Equatable {
    var preferredLanguage: String
    var translationLanguages: Set<String>
    var localeLanguage: String

    init(
        preferredLanguage: String,
        translationLanguages: Set<String>,
        localeLanguage: String = Locale.current.language.languageCode?.identifier ?? "en"
    ) {
        self.preferredLanguage = preferredLanguage
        self.translationLanguages = translationLanguages
        self.localeLanguage = localeLanguage
    }

    var targetLanguage: String {
        let requestedLanguage = preferredLanguage.isEmpty ? localeLanguage : preferredLanguage
        if TranslationLanguagePreferences.isAllowed(requestedLanguage, in: translationLanguages) {
            return requestedLanguage
        }
        if translationLanguages.contains("en") {
            return "en"
        }
        return translationLanguages.sorted().first ?? "en"
    }

    var preferredReplyLanguageFallback: String? {
        guard !preferredLanguage.isEmpty,
              TranslationLanguagePreferences.isAllowed(preferredLanguage, in: translationLanguages) else {
            return nil
        }
        return preferredLanguage
    }

    func allows(_ language: String) -> Bool {
        TranslationLanguagePreferences.isAllowed(language, in: translationLanguages)
    }
}

enum MainSceneTranslationNodePolicy {
    static func didChange(
        existing: [(id: String, text: String)]?,
        incoming: [(id: String, text: String)]
    ) -> Bool {
        guard let existing else { return true }
        guard existing.count == incoming.count else { return true }
        return zip(existing, incoming).contains { current, next in
            current.id != next.id || current.text != next.text
        }
    }
}

extension MainScene {

    var translationLanguageCodes: Set<String> {
        TranslationLanguagePreferences.parse(translationLanguagesRaw)
    }

    var translationPreferenceState: MainSceneTranslationPreferenceState {
        MainSceneTranslationPreferenceState(
            preferredLanguage: preferredLanguage,
            translationLanguages: translationLanguageCodes
        )
    }

    var translationTargetLanguage: String {
        translationPreferenceState.targetLanguage
    }

    var translatedThreadNodes: [String: [String: String]] {
        translationStore.allTranslatedNodes(target: translationTargetLanguage)
    }

    func translationPreferencesDidChange() {
        translationStore.clearCache()
    }

    func selectedThreadTranslationDidChange() {
        translationStore.clearCache()
    }

    @ViewBuilder
    func translationHeader() -> some View {
        TranslationToggleView(
            store: translationStore,
            detectedLanguage: detectThreadLanguage(),
            preferredLanguage: preferredLanguage,
            translationLanguages: translationLanguageCodes,
            autoTranslate: autoTranslate,
            messages: translationMessages,
            htmlMessageIds: translationHTMLMessageIDs
        )
    }

    func lastIncomingText() -> String? {
        if let lastIncoming = threadStore.messages.last(where: { !$0.isSentByMe }) {
            return lastIncoming.bestPlainText
        }
        return threadStore.messages.last?.bestPlainText
    }

    func detectThreadLanguage() -> String? {
        guard let text = lastIncomingText() else { return nil }
        guard let detected = NodeLanguageDetector.detect(text),
              translationPreferenceState.allows(detected.bcp47) else {
            return nil
        }
        return detected.bcp47
    }

    func detectReplyLanguage() -> String? {
        guard let text = lastIncomingText(), !text.isEmpty else {
            return preferredReplyLanguageFallback()
        }
        guard let detected = NodeLanguageDetector.detect(text),
              translationPreferenceState.allows(detected.bcp47) else {
            return preferredReplyLanguageFallback()
        }
        return detected.bcp47
    }

    func handleExtractedTranslationNodes(messageId: String, nodes: [TranslationTextNode]) {
        let incoming = nodes.map { ($0.id, $0.text) }
        if MainSceneTranslationNodePolicy.didChange(
            existing: translationStore.extractedNodes[messageId],
            incoming: incoming
        ) {
            _ = translationStore.nextGeneration(for: messageId)
            translationStore.clearNodeTranslations(for: messageId)
            if translationStore.showTranslated {
                translationStore.needsRetranslation = true
            }
        }
        translationStore.setExtractedNodes(for: messageId, nodes: incoming)
    }

    private var translationMessages: [(id: String, text: String)] {
        threadStore.messages.map { ($0.id, $0.bestPlainText) }
    }

    private var translationHTMLMessageIDs: Set<String> {
        Set(threadStore.messages.compactMap { $0.bodyHtml != nil ? $0.id : nil })
    }

    private func preferredReplyLanguageFallback() -> String? {
        translationPreferenceState.preferredReplyLanguageFallback
    }
}
