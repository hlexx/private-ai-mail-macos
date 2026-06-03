import Foundation
import Testing
import AppFoundation
@testable import SettingsFeature

@Suite("Preferences Persistence")
struct PreferencesPersistenceTests {

    private let defaults: UserDefaults

    init() {
        let suiteName = "com.test.PreferencesPersistence.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName)!
    }

    @Test func preferredLanguageDefaultsToEmpty() {
        let value = defaults.string(forKey: "pam.preferredLanguage") ?? ""
        #expect(value == "")
    }

    @Test func preferredLanguagePersistsAcrossReads() {
        defaults.set("ru", forKey: "pam.preferredLanguage")
        let readBack = defaults.string(forKey: "pam.preferredLanguage")
        #expect(readBack == "ru")
    }

    @Test func defaultToneDefaultsToWarm() {
        let value = defaults.string(forKey: "pam.defaultTone") ?? "warm"
        #expect(value == "warm")
    }

    @Test func defaultTonePersists() {
        defaults.set("direct", forKey: "pam.defaultTone")
        let readBack = defaults.string(forKey: "pam.defaultTone")
        #expect(readBack == "direct")
    }

    @Test func autoTranslateDefaultsToFalse() {
        let value = defaults.bool(forKey: "pam.autoTranslate")
        #expect(value == false)
    }

    @Test func autoTranslatePersists() {
        defaults.set(true, forKey: "pam.autoTranslate")
        let readBack = defaults.bool(forKey: "pam.autoTranslate")
        #expect(readBack == true)
    }

    @Test func translationLanguagesDefaultToEnglishRussianThai() {
        #expect(TranslationLanguagePreferences.defaultRawValue == "en,ru,th")
        #expect(TranslationLanguagePreferences.availableLanguages.map(\.code) == ["en", "ru", "th"])
    }

    @Test func translationLanguagesPersistAsNormalizedRawValue() {
        let selected: Set<String> = ["th", "en"]
        defaults.set(TranslationLanguagePreferences.rawValue(for: selected), forKey: TranslationLanguagePreferences.storageKey)

        let readBack = defaults.string(forKey: TranslationLanguagePreferences.storageKey)
        #expect(readBack == "en,th")
    }

    @Test func supportedLanguagesListIsNotEmpty() {
        #expect(!GeneralTab.supportedLanguages.isEmpty)
        #expect(GeneralTab.supportedLanguages.count == 16)
    }

    @Test func allLanguageCodesAreValidBCP47() {
        for lang in GeneralTab.supportedLanguages {
            let locale = Locale(identifier: lang.code)
            #expect(locale.language.languageCode != nil, "Invalid BCP-47 code: \(lang.code)")
        }
    }
}
