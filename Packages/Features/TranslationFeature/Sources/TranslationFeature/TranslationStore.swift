import Foundation
import NaturalLanguage
import Observation
import Persistence

@Observable
@MainActor
public final class TranslationStore {
    public private(set) var isTranslating = false
    public private(set) var error: (any Error)?
    public var showTranslated = false
    public private(set) var translatedTexts: [String: String] = [:]

    private let db: AppDatabase?

    public init(db: AppDatabase) {
        self.db = db
    }

    public init() {
        self.db = nil
    }

    // MARK: - Language Detection

    public nonisolated func detect(text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return language.rawValue
    }

    public nonisolated func detectWithConfidence(text: String) -> (language: String, confidence: Double)? {
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[language] ?? 0.0
        return (language.rawValue, confidence)
    }

    // MARK: - Translation Cache

    public func setTranslation(for messageId: String, text: String) {
        translatedTexts[messageId] = text
    }

    public func translatedText(for messageId: String) -> String? {
        translatedTexts[messageId]
    }

    public func setTranslating(_ value: Bool) {
        isTranslating = value
    }

    public func setError(_ err: (any Error)?) {
        error = err
    }

    public func clearCache() {
        translatedTexts.removeAll()
        showTranslated = false
    }
}
