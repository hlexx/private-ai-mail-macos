import Foundation

public struct TranslationLanguageOption: Sendable, Equatable {
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public enum TranslationLanguagePreferences {
    public static let storageKey = "pam.translationLanguages"
    public static let defaultRawValue = "en,ru,th"

    public static let availableLanguages: [TranslationLanguageOption] = [
        TranslationLanguageOption(code: "en", name: "English"),
        TranslationLanguageOption(code: "ru", name: "Russian"),
        TranslationLanguageOption(code: "th", name: "Thai"),
    ]

    public static var defaultCodes: Set<String> {
        parse(defaultRawValue)
    }

    public static func parse(_ rawValue: String) -> Set<String> {
        let supportedCodes = Set(availableLanguages.map(\.code))
        return Set(
            rawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { supportedCodes.contains($0) }
        )
    }

    public static func rawValue(for codes: Set<String>) -> String {
        availableLanguages
            .map(\.code)
            .filter { codes.contains($0) }
            .joined(separator: ",")
    }

    public static func isAllowed(_ language: String, in allowedCodes: Set<String>) -> Bool {
        guard !allowedCodes.isEmpty else { return false }
        let primaryLanguage = primarySubtag(language)
        return allowedCodes.contains { primarySubtag($0) == primaryLanguage }
    }

    private static func primarySubtag(_ language: String) -> String {
        language
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased() ?? language.lowercased()
    }
}
