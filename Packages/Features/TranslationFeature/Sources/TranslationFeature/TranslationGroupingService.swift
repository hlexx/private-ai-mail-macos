import Foundation

public struct NodeBatch: Sendable {
    public let sourceLanguage: String   // BCP-47
    public let nodes: [(id: String, text: String)]

    public init(sourceLanguage: String, nodes: [(id: String, text: String)]) {
        self.sourceLanguage = sourceLanguage
        self.nodes = nodes
    }
}

public enum TranslationGroupingService {

    /// Compare primary language subtags so "zh-Hans" matches "zh", "pt-BR" matches "pt", etc.
    static func languagesMatch(_ a: String, _ b: String) -> Bool {
        let primaryA = a.split(separator: "-").first.map(String.init) ?? a
        let primaryB = b.split(separator: "-").first.map(String.init) ?? b
        return primaryA.lowercased() == primaryB.lowercased()
    }

    public static func group(
        nodes: [(id: String, text: String)],
        preferredLanguage: String,
        allowedSourceLanguages: Set<String>? = nil
    ) -> (batches: [NodeBatch], skipped: Set<String>) {
        var bySource: [String: [(id: String, text: String)]] = [:]
        var skipped: Set<String> = []
        for node in nodes {
            guard let detected = NodeLanguageDetector.detect(node.text) else {
                skipped.insert(node.id)
                continue
            }
            if let allowedSourceLanguages,
               !isAllowed(detected.bcp47, in: allowedSourceLanguages) {
                skipped.insert(node.id)
                continue
            }
            if languagesMatch(detected.bcp47, preferredLanguage) {
                skipped.insert(node.id)
                continue
            }
            bySource[detected.bcp47, default: []].append((id: node.id, text: node.text))
        }
        let batches = bySource.map { NodeBatch(sourceLanguage: $0.key, nodes: $0.value) }
        return (batches, skipped)
    }

    private static func isAllowed(_ language: String, in allowedLanguages: Set<String>) -> Bool {
        guard !allowedLanguages.isEmpty else { return false }
        return allowedLanguages.contains { languagesMatch($0, language) }
    }
}
