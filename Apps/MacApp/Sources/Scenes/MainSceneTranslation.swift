import AppFoundation
import Foundation
import TranslationFeature

// Owns app-shell translation preferences and language detection wiring. Keep
// translation execution, cache semantics, and package behavior in
// TranslationFeature.
extension MainScene {

    var translationLanguageCodes: Set<String> {
        TranslationLanguagePreferences.parse(translationLanguagesRaw)
    }

    var translationTargetLanguage: String {
        let requestedLanguage = preferredLanguage.isEmpty
            ? (Locale.current.language.languageCode?.identifier ?? "en")
            : preferredLanguage
        if TranslationLanguagePreferences.isAllowed(requestedLanguage, in: translationLanguageCodes) {
            return requestedLanguage
        }
        if translationLanguageCodes.contains("en") {
            return "en"
        }
        return translationLanguageCodes.sorted().first ?? "en"
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
              TranslationLanguagePreferences.isAllowed(detected.bcp47, in: translationLanguageCodes) else {
            return nil
        }
        return detected.bcp47
    }

    func detectReplyLanguage() -> String? {
        guard let text = lastIncomingText(), !text.isEmpty else {
            return preferredReplyLanguageFallback()
        }
        guard let detected = NodeLanguageDetector.detect(text),
              TranslationLanguagePreferences.isAllowed(detected.bcp47, in: translationLanguageCodes) else {
            return preferredReplyLanguageFallback()
        }
        return detected.bcp47
    }

    private func preferredReplyLanguageFallback() -> String? {
        guard !preferredLanguage.isEmpty,
              TranslationLanguagePreferences.isAllowed(preferredLanguage, in: translationLanguageCodes) else {
            return nil
        }
        return preferredLanguage
    }
}
