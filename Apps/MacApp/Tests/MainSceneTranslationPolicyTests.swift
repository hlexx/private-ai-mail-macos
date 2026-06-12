import AppFoundation
import Testing
@testable import PrivateAIMail

@Suite("MainScene translation policy")
struct MainSceneTranslationPolicyTests {
    @Test func storageKeyPreservesExistingTranslationLanguagePreference() {
        #expect(TranslationLanguagePreferences.storageKey == "pam.translationLanguages")
    }

    @Test func preferredLanguageWinsWhenAllowed() {
        let state = makeState(preferredLanguage: "ru", translationLanguages: ["en", "ru", "th"])

        #expect(state.targetLanguage == "ru")
        #expect(state.preferredReplyLanguageFallback == "ru")
    }

    @Test func emptyPreferredLanguageUsesAllowedLocaleLanguage() {
        let state = makeState(preferredLanguage: "", translationLanguages: ["en", "ru"], localeLanguage: "ru")

        #expect(state.targetLanguage == "ru")
        #expect(state.preferredReplyLanguageFallback == nil)
    }

    @Test func disallowedPreferredLanguageFallsBackToEnglishWhenAvailable() {
        let state = makeState(preferredLanguage: "de", translationLanguages: ["en", "ru"], localeLanguage: "de")

        #expect(state.targetLanguage == "en")
        #expect(state.preferredReplyLanguageFallback == nil)
    }

    @Test func targetLanguageFallsBackToFirstAllowedLanguageWhenEnglishIsUnavailable() {
        let state = makeState(preferredLanguage: "de", translationLanguages: ["th", "ru"], localeLanguage: "de")

        #expect(state.targetLanguage == "ru")
    }

    @Test func nodePolicyInvalidatesOnlyWhenExtractedNodesChange() {
        let existing = [
            (id: "node-1", text: "Hello"),
            (id: "node-2", text: "World"),
        ]

        #expect(!MainSceneTranslationNodePolicy.didChange(existing: existing, incoming: existing))
        #expect(
            MainSceneTranslationNodePolicy.didChange(
                existing: existing,
                incoming: [(id: "node-1", text: "Hello")]
            )
        )
        #expect(
            MainSceneTranslationNodePolicy.didChange(
                existing: existing,
                incoming: [
                    (id: "node-1", text: "Hello"),
                    (id: "node-2", text: "Changed"),
                ]
            )
        )
    }

    private func makeState(
        preferredLanguage: String,
        translationLanguages: Set<String>,
        localeLanguage: String = "en"
    ) -> MainSceneTranslationPreferenceState {
        MainSceneTranslationPreferenceState(
            preferredLanguage: preferredLanguage,
            translationLanguages: translationLanguages,
            localeLanguage: localeLanguage
        )
    }
}
