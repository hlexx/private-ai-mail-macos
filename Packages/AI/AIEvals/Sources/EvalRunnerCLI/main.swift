import AIEvals
import AIKit
import AIRuntime
import Foundation

/// CLI entry point that runs the eval corpus against an AIService
/// and prints a markdown report to stdout.
///
/// Usage: swift run EvalRunnerCLI
///
/// When the real model is installed at the expected path, uses
/// ThreadBriefService backed by MLXBackend for real on-device inference.
/// Otherwise falls back to a stub service for offline/CI runs.

/// A stub service for offline eval runs (no GPU required).
/// Returns a brief that mirrors source content for high faithfulness scores.
struct StubEvalService: AIService {
    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        let firstSender = input.messages.first?.from ?? "unknown"
        let bodySnippet = input.messages.first?.bodyText.prefix(80) ?? ""

        return AIThreadBrief(
            summary: "Summary of thread from \(firstSender): \(bodySnippet)",
            request: input.messages.count > 1 ? "Review and respond" : nil,
            deadline: nil,
            risk: nil,
            nextStep: nil,
            evidence: [String(bodySnippet)],
            confidence: 0.7
        )
    }
}

let corpus = EvalCorpus.threads

let service: any AIService
let modelManager = ModelManager()

if await modelManager.installedURL() != nil {
    fputs("Using real MLXBackend (model found)\n", stderr)
    service = ThreadBriefService.live(modelManager: modelManager)
} else {
    fputs("WARNING: Model not installed. Using stub service. Download the model first for real eval.\n", stderr)
    service = StubEvalService()
}

let runner = EvalRunner()
let report = try await runner.run(corpus: corpus, service: service)

print(report.markdownReport())

if report.schemaValidityRate < 1.0 {
    fputs("\nWARNING: Schema validity below 100%\n", stderr)
}
