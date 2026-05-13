import Foundation

/// Data shape for a thread brief produced by the AI engine.
/// Matches the design's `brief` object in `data.js`.
public struct ThreadBriefViewData: Sendable, Equatable {
    public let summary: String
    public let request: String?
    public let deadline: String?
    public let risk: String?
    public let nextStep: String?
    public let confidence: Double
    public let evidence: [String]

    public init(
        summary: String,
        request: String? = nil,
        deadline: String? = nil,
        risk: String? = nil,
        nextStep: String? = nil,
        confidence: Double,
        evidence: [String] = []
    ) {
        self.summary = summary
        self.request = request
        self.deadline = deadline
        self.risk = risk
        self.nextStep = nextStep
        self.confidence = confidence
        self.evidence = evidence
    }
}
