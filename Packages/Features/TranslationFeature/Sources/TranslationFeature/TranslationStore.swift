import Foundation
import NaturalLanguage
import Observation
import Persistence

@Observable
@MainActor
public final class TranslationStore {
    public private(set) var inflightBatches: Int = 0
    public var isTranslating: Bool { inflightBatches > 0 }
    public private(set) var error: (any Error)?
    public var showTranslated = false
    public private(set) var translatedTexts: [String: String] = [:]
    public private(set) var translatedNodes: [String: [String: String]] = [:]
    public private(set) var translationGeneration: [String: Int] = [:]
    public private(set) var nodeTranslationComplete: Set<String> = []

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

    // MARK: - Translation Cache (plain text fallback)

    public func setTranslation(for messageId: String, text: String) {
        translatedTexts[messageId] = text
    }

    public func translatedText(for messageId: String) -> String? {
        translatedTexts[messageId]
    }

    // MARK: - Translation Cache (per-node HTML)

    public func setNodeTranslations(for messageId: String, nodes: [String: String]) {
        translatedNodes[messageId] = nodes
    }

    public func nodeTranslations(for messageId: String) -> [String: String]? {
        translatedNodes[messageId]
    }

    public func mergeNodeTranslations(for messageId: String, nodes: [String: String]) {
        if translatedNodes[messageId] == nil {
            translatedNodes[messageId] = nodes
        } else {
            translatedNodes[messageId]?.merge(nodes) { _, new in new }
        }
    }

    public func clearNodeTranslations(for messageId: String) {
        translatedNodes.removeValue(forKey: messageId)
        nodeTranslationComplete.remove(messageId)
    }

    public func nextGeneration(for messageId: String) -> Int {
        let gen = (translationGeneration[messageId] ?? 0) + 1
        translationGeneration[messageId] = gen
        return gen
    }

    public func currentGeneration(for messageId: String) -> Int {
        translationGeneration[messageId] ?? 0
    }

    // MARK: - Extracted Nodes (pending translation)

    public private(set) var extractedNodes: [String: [(id: String, text: String)]] = [:]

    public func setExtractedNodes(for messageId: String, nodes: [(id: String, text: String)]) {
        extractedNodes[messageId] = nodes
    }

    // MARK: - State Management

    /// Set by the extraction callback when nodes arrive after the initial
    /// translation pass has already completed. TranslationToggleView observes
    /// this flag to re-trigger translation for HTML messages.
    public var needsRetranslation = false

    public func incrementInflight() {
        inflightBatches += 1
    }

    public func decrementInflight() {
        inflightBatches = max(0, inflightBatches - 1)
    }

    public func setError(_ err: (any Error)?) {
        error = err
    }

    public func markNodeTranslationComplete(for messageId: String) {
        nodeTranslationComplete.insert(messageId)
    }

    public func clearCache() {
        translatedTexts.removeAll()
        translatedNodes.removeAll()
        extractedNodes.removeAll()
        translationGeneration.removeAll()
        nodeTranslationComplete.removeAll()
        inflightBatches = 0
        needsRetranslation = false
        showTranslated = false
    }
}
