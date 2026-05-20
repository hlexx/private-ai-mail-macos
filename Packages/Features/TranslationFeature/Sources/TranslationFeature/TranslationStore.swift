import Foundation
import Observation
import Persistence

public struct TranslatedFragment: Sendable, Equatable {
    public let text: String
    public let source: String
    public let target: String

    public init(text: String, source: String, target: String) {
        self.text = text
        self.source = source
        self.target = target
    }
}

@Observable
@MainActor
public final class TranslationStore {
    public private(set) var inflightBatches: Int = 0
    public var isTranslating: Bool { inflightBatches > 0 }
    public private(set) var error: (any Error)?
    public var showTranslated = false
    public private(set) var translatedTexts: [String: String] = [:]
    public private(set) var translatedNodes: [String: [String: TranslatedFragment]] = [:]
    public private(set) var translationGeneration: [String: Int] = [:]
    /// Maps messageId -> set of target languages for which translation is complete.
    public private(set) var nodeTranslationComplete: [String: Set<String>] = [:]

    private let db: AppDatabase?

    public init(db: AppDatabase) {
        self.db = db
    }

    public init() {
        self.db = nil
    }

    // MARK: - Translation Cache (plain text fallback)

    public func setTranslation(for messageId: String, text: String) {
        translatedTexts[messageId] = text
    }

    public func translatedText(for messageId: String) -> String? {
        translatedTexts[messageId]
    }

    // MARK: - Translation Cache (per-node HTML)

    public func setNodeTranslations(for messageId: String, fragments: [String: TranslatedFragment]) {
        translatedNodes[messageId] = fragments
    }

    /// Returns node translations filtered to the given target language.
    /// Only fragments whose `target` matches are included.
    public func nodeTranslations(for messageId: String, target: String) -> [String: String]? {
        guard let fragments = translatedNodes[messageId] else { return nil }
        var result: [String: String] = [:]
        for (nodeId, fragment) in fragments where fragment.target == target {
            result[nodeId] = fragment.text
        }
        return result.isEmpty ? nil : result
    }

    /// Returns all translated nodes grouped by messageId, filtered to the given target.
    public func allTranslatedNodes(target: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for (messageId, fragments) in translatedNodes {
            var filtered: [String: String] = [:]
            for (nodeId, fragment) in fragments where fragment.target == target {
                filtered[nodeId] = fragment.text
            }
            if !filtered.isEmpty {
                result[messageId] = filtered
            }
        }
        return result
    }

    public func mergeNodeTranslations(for messageId: String, fragments: [String: TranslatedFragment]) {
        if translatedNodes[messageId] == nil {
            translatedNodes[messageId] = fragments
        } else {
            translatedNodes[messageId]?.merge(fragments) { _, new in new }
        }
    }

    public func clearNodeTranslations(for messageId: String) {
        translatedNodes.removeValue(forKey: messageId)
        nodeTranslationComplete.removeValue(forKey: messageId)
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

    public func markNodeTranslationComplete(for messageId: String, target: String) {
        nodeTranslationComplete[messageId, default: []].insert(target)
    }

    public func isNodeTranslationComplete(for messageId: String, target: String) -> Bool {
        nodeTranslationComplete[messageId]?.contains(target) ?? false
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
