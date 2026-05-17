import AIKit
import Foundation

public final class MockAIService: AIService, @unchecked Sendable {
    public var stubbedBrief: AIThreadBrief?
    public var stubbedReply: AIThreadReply?
    public var stubbedError: (any Error)?
    public private(set) var threadBriefCallCount = 0
    public private(set) var draftReplyCallCount = 0
    public private(set) var lastInput: AIThreadInput?
    public private(set) var lastTone: AIReplyTone?
    public private(set) var lastReplyLanguage: String?

    public init(
        stubbedBrief: AIThreadBrief? = nil,
        stubbedReply: AIThreadReply? = nil,
        stubbedError: (any Error)? = nil
    ) {
        self.stubbedBrief = stubbedBrief
        self.stubbedReply = stubbedReply
        self.stubbedError = stubbedError
    }

    public func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        threadBriefCallCount += 1
        lastInput = input
        if let error = stubbedError { throw error }
        guard let brief = stubbedBrief else {
            throw AIError.inferenceFailed(
                NSError(domain: "MockAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No stubbed brief"])
            )
        }
        return brief
    }

    public func draftReply(
        _ input: AIThreadInput,
        tone: AIReplyTone,
        locale: Locale,
        replyLanguage: String?
    ) async throws -> AIThreadReply {
        draftReplyCallCount += 1
        lastInput = input
        lastTone = tone
        lastReplyLanguage = replyLanguage
        if let error = stubbedError { throw error }
        guard let reply = stubbedReply else {
            throw AIError.inferenceFailed(
                NSError(domain: "MockAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No stubbed reply"])
            )
        }
        return reply
    }
}
