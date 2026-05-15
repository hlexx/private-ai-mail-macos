import Foundation
import Testing
@testable import AIRuntime
import AIPrompts

// MARK: - Helpers

final class LockedBox<T: Sendable>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) { _value = value }

    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - FakeLLMRunner

final class FakeLLMRunner: LLMRunner, @unchecked Sendable {
    var loadCalled = false
    var generateCallCount = 0
    var responses: [String] = []
    var shouldThrow: (any Error)?
    var delayNanoseconds: UInt64 = 0

    func load(from modelDirectory: URL) async throws {
        loadCalled = true
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        onToken: @Sendable (String) -> Void
    ) async throws -> String {
        try Task.checkCancellation()

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if let error = shouldThrow {
            throw error
        }

        let index = min(generateCallCount, responses.count - 1)
        generateCallCount += 1

        guard index >= 0, index < responses.count else {
            fatalError("FakeLLMRunner: no response configured for call \(generateCallCount)")
        }

        let response = responses[index]
        for char in response {
            try Task.checkCancellation()
            onToken(String(char))
        }
        return response
    }
}

// MARK: - Test Helpers

private let validBriefJSON = """
{
  "summary": "Contract review discussion",
  "request": "Review and sign the contract by Friday",
  "deadline": "2026-05-16",
  "risk": "Late signing penalty clause",
  "nextStep": "Send signed copy to legal",
  "evidence": ["Message from Alice on May 12"],
  "confidence": 0.85
}
"""

private let informationalBriefJSON = """
{
  "summary": "Weekly team digest",
  "request": null,
  "deadline": null,
  "risk": null,
  "nextStep": null,
  "evidence": ["Digest from Notion bot"],
  "confidence": 0.6
}
"""

private let malformedJSON = "This is not JSON at all {"

private let invalidSchemaJSON = """
{
  "summary": "Test",
  "evidence": ["a"],
  "confidence": 1.5
}
"""

private func makeSampleMessages() -> [PromptMessage] {
    [
        PromptMessage(
            from: "alice@example.com",
            sentAt: Date(timeIntervalSince1970: 1_715_500_000),
            bodyText: "Please review the attached contract."
        ),
    ]
}

private func makeModelManager() -> ModelManager {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mlxbackend-test-\(UUID().uuidString)")
    return ModelManager(modelsRoot: tempDir)
}

// MARK: - Tests

@Suite("MLXBackend")
struct MLXBackendTests {

    @Test("Happy path: valid JSON response returns parsed brief")
    func happyPath() async throws {
        let runner = FakeLLMRunner()
        runner.responses = [validBriefJSON]

        let manager = makeModelManager()
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner
        )

        let brief = try await backend.threadBrief(
            messages: makeSampleMessages(),
            attachments: []
        )

        #expect(brief.summary == "Contract review discussion")
        #expect(brief.request == "Review and sign the contract by Friday")
        #expect(brief.deadline == "2026-05-16")
        #expect(brief.confidence == 0.85)
        #expect(brief.evidence == ["Message from Alice on May 12"])
    }

    @Test("Informational thread: nil optional fields")
    func informationalThread() async throws {
        let runner = FakeLLMRunner()
        runner.responses = [informationalBriefJSON]

        let manager = makeModelManager()
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner
        )

        let brief = try await backend.threadBrief(
            messages: makeSampleMessages(),
            attachments: []
        )

        #expect(brief.summary == "Weekly team digest")
        #expect(brief.request == nil)
        #expect(brief.deadline == nil)
        #expect(brief.risk == nil)
        #expect(brief.nextStep == nil)
    }

    @Test("Malformed output triggers retry, then succeeds on second attempt")
    func retryOnMalformedOutput() async throws {
        let runner = FakeLLMRunner()
        runner.responses = [malformedJSON, validBriefJSON]

        let manager = makeModelManager()
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner,
            maxRetries: 1
        )

        let brief = try await backend.threadBrief(
            messages: makeSampleMessages(),
            attachments: []
        )

        #expect(brief.summary == "Contract review discussion")
        #expect(runner.generateCallCount == 2)
    }

    @Test("Retry exhaustion throws invalidStructuredOutput")
    func retryExhaustion() async throws {
        let runner = FakeLLMRunner()
        runner.responses = [malformedJSON, malformedJSON]

        let manager = makeModelManager()
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner,
            maxRetries: 1
        )

        await #expect(throws: MLXBackendError.self) {
            try await backend.threadBrief(
                messages: makeSampleMessages(),
                attachments: []
            )
        }
    }

    @Test("Schema violation after retries throws invalidStructuredOutput")
    func schemaViolationExhaustsRetries() async throws {
        let runner = FakeLLMRunner()
        runner.responses = [invalidSchemaJSON, invalidSchemaJSON]

        let manager = makeModelManager()
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner,
            maxRetries: 1
        )

        await #expect(throws: MLXBackendError.self) {
            try await backend.threadBrief(
                messages: makeSampleMessages(),
                attachments: []
            )
        }
    }

    @Test("Cancellation propagates correctly")
    func cancellation() async throws {
        let runner = FakeLLMRunner()
        runner.responses = [validBriefJSON]
        runner.delayNanoseconds = 2_000_000_000 // 2 seconds

        let manager = makeModelManager()
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner
        )

        let started = LockedBox(false)

        let task = Task {
            started.value = true
            return try await backend.threadBrief(
                messages: makeSampleMessages(),
                attachments: []
            )
        }

        // Spin until the task has started
        while !started.value {
            await Task.yield()
        }
        // Small additional yield to ensure it enters the actor
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        task.cancel()

        let threw: Bool
        do {
            _ = try await task.value
            threw = false
        } catch {
            threw = true
        }

        #expect(threw, "Expected cancellation to throw an error")
    }

    @Test("Runner error wraps as inferenceFailed")
    func runnerError() async throws {
        let runner = FakeLLMRunner()
        runner.shouldThrow = NSError(domain: "test", code: 42)
        runner.responses = []

        let manager = makeModelManager()
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner
        )

        await #expect(throws: MLXBackendError.self) {
            try await backend.threadBrief(
                messages: makeSampleMessages(),
                attachments: []
            )
        }
    }

    @Test("Markdown-fenced JSON response is parsed correctly")
    func markdownFencedResponse() async throws {
        let fenced = """
        ```json
        \(validBriefJSON)
        ```
        """
        let runner = FakeLLMRunner()
        runner.responses = [fenced]

        let manager = makeModelManager()
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner
        )

        let brief = try await backend.threadBrief(
            messages: makeSampleMessages(),
            attachments: []
        )

        #expect(brief.summary == "Contract review discussion")
    }
}
