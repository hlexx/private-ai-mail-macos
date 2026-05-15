import Foundation

public struct AIThreadBrief: Sendable, Equatable {
    public let summary: String?
    public let request: String?
    public let deadline: String?
    public let risk: String?
    public let nextStep: String?
    public let evidence: [String]
    public let confidence: Double

    public init(
        summary: String? = nil,
        request: String? = nil,
        deadline: String? = nil,
        risk: String? = nil,
        nextStep: String? = nil,
        evidence: [String] = [],
        confidence: Double
    ) {
        self.summary = summary
        self.request = request
        self.deadline = deadline
        self.risk = risk
        self.nextStep = nextStep
        self.evidence = evidence
        self.confidence = confidence
    }
}
