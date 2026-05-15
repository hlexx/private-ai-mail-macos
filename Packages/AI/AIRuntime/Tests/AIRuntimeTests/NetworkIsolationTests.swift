import Foundation
import Testing
@testable import AIRuntime
import AIPrompts

// MARK: - Spy URLProtocol

/// URLProtocol subclass that records any attempted network requests.
/// If `startLoading` is called, it means some code tried to make a
/// network call through URLSession.shared or a session using
/// the default configuration with this protocol registered.
private final class SpyURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset() {
        requestCount = 0
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true // intercept everything
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        SpyURLProtocol.requestCount += 1
        SpyURLProtocol.lastRequest = request
        // Fail the request immediately — inference code should never reach here
        let error = NSError(
            domain: "NetworkIsolationTest",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected network request during inference"]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}

// MARK: - Tests

@Suite("NetworkIsolation")
struct NetworkIsolationTests {

    @Test("MLXBackend.threadBrief makes zero network requests")
    func noNetworkDuringInference() async throws {
        // Register the spy protocol on the shared session's configuration
        URLProtocol.registerClass(SpyURLProtocol.self)
        defer { URLProtocol.unregisterClass(SpyURLProtocol.self) }
        SpyURLProtocol.reset()

        // Set up a FakeLLMRunner that returns valid JSON without any network calls
        let runner = FakeLLMRunner()
        runner.responses = ["""
        {
          "summary": "Test summary",
          "request": null,
          "deadline": null,
          "risk": null,
          "nextStep": null,
          "evidence": [],
          "confidence": 0.7
        }
        """]

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("network-isolation-test-\(UUID().uuidString)")
        let manager = ModelManager(modelsRoot: tempDir)
        let backend = MLXBackend(
            modelManager: manager,
            runner: runner
        )

        let messages = [
            PromptMessage(
                from: "sender@example.com",
                sentAt: Date(),
                bodyText: "Hello, this is a test message."
            ),
        ]

        _ = try await backend.threadBrief(
            messages: messages,
            attachments: []
        )

        #expect(
            SpyURLProtocol.requestCount == 0,
            "MLXBackend.threadBrief() must not make any network requests, but \(SpyURLProtocol.requestCount) were detected"
        )
    }
}
