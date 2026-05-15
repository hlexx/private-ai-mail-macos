import Foundation
import Testing
@testable import AIRuntime

private let liveTestsEnabled: Bool = {
    guard ProcessInfo.processInfo.environment["RB_RUN_REAL_MLX_TESTS"] == "1" else {
        return false
    }
    let dir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PrivateAIMail/models/\(GemmaModelSpec.directoryName)", isDirectory: true)
    return FileManager.default.fileExists(atPath: dir.path)
}()

/// Live integration tests for MLXLLMRunner.
/// Requires a real model on disk and Metal GPU — skipped on CI.
/// Run locally with: RB_RUN_REAL_MLX_TESTS=1 swift test --filter MLXLLMRunnerLiveTests
@Suite(.disabled(if: !liveTestsEnabled, "RB_RUN_REAL_MLX_TESTS not set or model not found"))
struct MLXLLMRunnerLiveTests {
    static var modelDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateAIMail/models/\(GemmaModelSpec.directoryName)", isDirectory: true)
    }

    @Test(.timeLimit(.minutes(2)))
    func loadAndGenerateShortOutput() async throws {
        let runner = MLXLLMRunner()
        try await runner.load(from: Self.modelDirectory)

        #expect(runner.isLoaded)

        let output = try await runner.generate(
            systemPrompt: "You are an email assistant. Return JSON with a \"summary\" field.",
            userPrompt: "Subject: Meeting tomorrow\nBody: Let's meet at 3pm to discuss the project.",
            maxTokens: 64,
            onToken: { _ in }
        )

        #expect(output.hasPrefix("{"), "Output should start with {, got: \(output.prefix(20))")
        #expect(output.contains("summary"), "Output should contain 'summary' key, got: \(output.prefix(100))")
    }
}
