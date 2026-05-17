import Foundation

public protocol AIService: Sendable {
    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief
    func draftReply(
        _ input: AIThreadInput,
        tone: AIReplyTone,
        locale: Locale,
        replyLanguage: String?
    ) async throws -> AIThreadReply
}

public enum AIReplyTone: String, Sendable, CaseIterable {
    case concise, warm, direct
}

public struct AIThreadReply: Sendable, Equatable {
    public let body: String
    public let evidenceMessageIDs: [String]
    public let detectedReplyLanguage: String
    public let confidence: Double

    public init(
        body: String,
        evidenceMessageIDs: [String] = [],
        detectedReplyLanguage: String = "en",
        confidence: Double = 0.8
    ) {
        self.body = body
        self.evidenceMessageIDs = evidenceMessageIDs
        self.detectedReplyLanguage = detectedReplyLanguage
        self.confidence = confidence
    }
}
