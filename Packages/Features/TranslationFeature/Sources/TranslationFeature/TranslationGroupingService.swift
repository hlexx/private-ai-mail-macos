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
    public static func group(
        nodes: [(id: String, text: String)],
        preferredLanguage: String
    ) -> (batches: [NodeBatch], skipped: Set<String>) {
        var bySource: [String: [(id: String, text: String)]] = [:]
        var skipped: Set<String> = []
        for node in nodes {
            guard let detected = NodeLanguageDetector.detect(node.text) else {
                skipped.insert(node.id)
                continue
            }
            if detected.bcp47 == preferredLanguage {
                skipped.insert(node.id)
                continue
            }
            bySource[detected.bcp47, default: []].append((id: node.id, text: node.text))
        }
        let batches = bySource.map { NodeBatch(sourceLanguage: $0.key, nodes: $0.value) }
        return (batches, skipped)
    }
}
