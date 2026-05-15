import AIKit
import Foundation

public final class MockAIService: AIService, @unchecked Sendable {
    public var stubbedBrief: AIThreadBrief?
    public var stubbedError: (any Error)?
    public private(set) var threadBriefCallCount = 0
    public private(set) var lastInput: AIThreadInput?

    public init(
        stubbedBrief: AIThreadBrief? = nil,
        stubbedError: (any Error)? = nil
    ) {
        self.stubbedBrief = stubbedBrief
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
}
