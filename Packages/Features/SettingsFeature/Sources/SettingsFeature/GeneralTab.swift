import AppFoundation
import DesignSystem
import SwiftUI

public struct GeneralTab: View {
    @AppStorage("pam.preferredLanguage") private var preferredLanguage: String = ""
    @AppStorage("pam.defaultTone") private var defaultTone: String = "warm"
    @AppStorage("pam.autoTranslate") private var autoTranslate: Bool = false
    @AppStorage(TranslationLanguagePreferences.storageKey) private var translationLanguagesRaw: String = TranslationLanguagePreferences.defaultRawValue

    public init() {}

    public var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: "general.preferredLanguage", defaultValue: "Preferred language"),
                    selection: $preferredLanguage
                ) {
                    Text(String(localized: "general.language.system", defaultValue: "System default"))
                        .tag("")
                    Divider()
                    ForEach(Self.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Picker(
                    String(localized: "general.defaultTone", defaultValue: "Default reply tone"),
                    selection: $defaultTone
                ) {
                    Text(String(localized: "general.tone.concise", defaultValue: "Concise")).tag("concise")
                    Text(String(localized: "general.tone.warm", defaultValue: "Warm")).tag("warm")
                    Text(String(localized: "general.tone.direct", defaultValue: "Direct")).tag("direct")
                }

                Toggle(
                    String(localized: "general.autoTranslate", defaultValue: "Auto-translate foreign threads"),
                    isOn: $autoTranslate
                )

                translationLanguagesGroup
            } header: {
                Text(String(localized: "general.section.language", defaultValue: "Language & AI"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "general.section.language.footer",
                        defaultValue: "When auto-translate is on, threads in a foreign language show the translated version by default."
                    ))
                    Text(String(
                        localized: "general.section.language.mixedHint",
                        defaultValue: "Only text in a different language is translated. Mixed-language emails translate only the non-preferred parts."
                    ))
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.rbBgCanvas)
        .padding()
    }

    private var translationLanguagesGroup: some View {
        VStack(alignment: .leading, spacing: RBSpace.s2) {
            Text(String(localized: "general.translationLanguages", defaultValue: "Translation languages"))
                .font(.headline)

            translationLanguageOptions

            if selectedTranslationLanguages.isEmpty {
                Text(String(
                    localized: "general.translationLanguages.emptyHint",
                    defaultValue: "No languages are selected, so translation is disabled."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.top, RBSpace.s1)
    }

    @ViewBuilder
    private var translationLanguageOptions: some View {
        if TranslationLanguagePreferences.availableLanguages.count <= Self.translationLanguageInlineLimit {
            HStack(alignment: .firstTextBaseline, spacing: RBSpace.s5) {
                ForEach(TranslationLanguagePreferences.availableLanguages, id: \.code) { language in
                    Toggle(language.name, isOn: translationLanguageBinding(for: language.code))
                        .frame(minWidth: TranslationLanguagesLayout.optionMinWidth, alignment: .leading)
                }
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: TranslationLanguagesLayout.optionMinWidth),
                        alignment: .leading
                    ),
                ],
                alignment: .leading,
                spacing: RBSpace.s2
            ) {
                ForEach(TranslationLanguagePreferences.availableLanguages, id: \.code) { language in
                    Toggle(language.name, isOn: translationLanguageBinding(for: language.code))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var selectedTranslationLanguages: Set<String> {
        TranslationLanguagePreferences.parse(translationLanguagesRaw)
    }

    private func translationLanguageBinding(for code: String) -> Binding<Bool> {
        Binding {
            selectedTranslationLanguages.contains(code)
        } set: { isSelected in
            var next = selectedTranslationLanguages
            if isSelected {
                next.insert(code)
            } else {
                next.remove(code)
            }
            translationLanguagesRaw = TranslationLanguagePreferences.rawValue(for: next)
        }
    }

    nonisolated static let supportedLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("ru", "Русский"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("pt", "Português"),
        ("zh-Hans", "中文 (简体)"),
        ("zh-Hant", "中文 (繁體)"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("ar", "العربية"),
        ("hi", "हिन्दी"),
        ("tr", "Türkçe"),
        ("pl", "Polski"),
        ("nl", "Nederlands"),
    ]

    nonisolated static let translationLanguageInlineLimit = 4
}

enum TranslationLanguagesLayout {
    static let optionMinWidth: CGFloat = 108
}
