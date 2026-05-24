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

    func draftReply(
        _ input: AIThreadInput,
        tone _: AIReplyTone,
        locale _: Locale,
        replyLanguage _: String?
    ) async throws -> AIThreadReply {
        let body = input.messages.first?.bodyText.prefix(80) ?? "Thanks, I will review this."
        return AIThreadReply(body: "Draft response based on: \(body)")
    }
}

let corpus = EvalCorpus.threads

let service: any AIService
let modelManager = ModelManager()

if await modelManager.installedURL() != nil {
    fputs("Using real MLXBackend (model found)\n", stderr)
    service = ThreadBriefService.live(modelManager: modelManager)
} else if ProcessInfo.processInfo.environment["RB_ALLOW_STUB_EVALS"] == "1" {
    fputs("WARNING: Model not installed. Using stub service (RB_ALLOW_STUB_EVALS=1).\n", stderr)
    service = StubEvalService()
} else {
    fputs("ERROR: Model not installed. Download the model first for real eval.\n", stderr)
    fputs("To run with stub data (not for baseline reports), set RB_ALLOW_STUB_EVALS=1\n", stderr)
    exit(1)
}

let runner = EvalRunner()
let report = try await runner.run(corpus: corpus, service: service)

print(report.markdownReport())

if report.schemaValidityRate < 1.0 {
    fputs("\nWARNING: Schema validity below 100%\n", stderr)
}
