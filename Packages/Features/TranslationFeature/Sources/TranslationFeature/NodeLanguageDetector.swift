import Foundation
import NaturalLanguage

public struct DetectedLanguage: Sendable, Equatable {
    public let bcp47: String
    public let confidence: Double
}

public enum NodeLanguageDetector {
    /// Detect the dominant language of a single text fragment.
    /// Returns `nil` for fragments shorter than `minimumLength`
    /// characters — those are too noisy to detect reliably and
    /// should pass through untranslated.
    public static func detect(
        _ text: String,
        minimumLength: Int = 4,
        minimumConfidence: Double = 0.5
    ) -> DetectedLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let best = hypotheses.max(by: { $0.value < $1.value }),
              best.value >= minimumConfidence else { return nil }
        return DetectedLanguage(bcp47: best.key.rawValue, confidence: best.value)
    }
}
