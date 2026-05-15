import AIPrompts
import Foundation
import os

/// Records latency samples from MLXBackend inference calls.
/// Conform to this protocol and inject into MLXBackend to capture
/// real timing data programmatically (e.g. from AIEvals).
public protocol LatencyRecorder: Sendable {
    func record(label: String, duration: Duration)
}

/// On-device LLM backend for generating thread briefs via MLX + Gemma.
///
/// Public API uses AIPrompts types (not AIKit) to avoid circular dependencies.
/// The AIKit layer wraps this in an AIService adapter (see Task 7).
public actor MLXBackend {
    private let modelManager: ModelManager
    private let runner: any LLMRunner
    private let maxOutputTokens: Int
    private let maxRetries: Int
    private let latencyRecorder: (any LatencyRecorder)?

    private var isModelLoaded = false

    private static let logger = Logger(
        subsystem: "com.privateaimail.airuntime",
        category: "MLXBackend"
    )

    public init(
        modelManager: ModelManager,
        maxOutputTokens: Int = 512,
        maxRetries: Int = 2,
        latencyRecorder: (any LatencyRecorder)? = nil
    ) {
        self.modelManager = modelManager
        self.runner = MLXLLMRunner()
        self.maxOutputTokens = maxOutputTokens
        self.maxRetries = maxRetries
        self.latencyRecorder = latencyRecorder
    }

    init(
        modelManager: ModelManager,
        runner: any LLMRunner,
        maxOutputTokens: Int = 512,
        maxRetries: Int = 1,
        latencyRecorder: (any LatencyRecorder)? = nil
    ) {
        self.modelManager = modelManager
        self.runner = runner
        self.maxOutputTokens = maxOutputTokens
        self.maxRetries = maxRetries
        self.latencyRecorder = latencyRecorder
    }

    // MARK: - Public API

    /// Generate a thread brief from the given messages and attachments.
    /// Actor isolation serializes concurrent calls so MLX state is never
    /// accessed concurrently. Cancellation propagates through the caller's task.
    public func threadBrief(
        messages: [PromptMessage],
        attachments: [PromptAttachment]
    ) async throws -> ParsedThreadBrief {
        try Task.checkCancellation()

        let systemPrompt = ThreadBriefPrompt.systemPrompt
        let userPrompt = ThreadBriefPrompt.taskPrompt(
            messages: messages,
            attachments: attachments
        )

        let start = ContinuousClock.now
        var lastError: (any Error)?

        for attempt in 0 ... maxRetries {
            try Task.checkCancellation()

            do {
                let rawOutput = try await runner.generate(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: maxOutputTokens,
                    onToken: { _ in }
                )

                let parsed = try ThreadBriefParser.parse(rawOutput)

                let elapsed = ContinuousClock.now - start
                Self.logger.info(
                    "Thread brief generated in \(elapsed) (attempt \(attempt + 1))"
                )
                latencyRecorder?.record(label: "threadBrief", duration: elapsed)

                return parsed
            } catch is CancellationError {
                throw CancellationError()
            } catch let parseError as ThreadBriefParser.ParseError {
                lastError = parseError
                if attempt < maxRetries {
                    Self.logger.warning(
                        "Malformed output on attempt \(attempt + 1), retrying"
                    )
                    continue
                }
            } catch let runnerError as MLXLLMRunnerError where runnerError.isRetryable {
                lastError = runnerError
                if attempt < maxRetries {
                    Self.logger.warning(
                        "Non-JSON output on attempt \(attempt + 1), retrying"
                    )
                    continue
                }
            } catch {
                throw MLXBackendError.inferenceFailed(error)
            }
        }

        let diagnostic: String
        if let parseError = lastError as? ThreadBriefParser.ParseError {
            switch parseError {
            case .invalidJSON(let raw): diagnostic = raw
            case .schemaViolation(let msg): diagnostic = msg
            }
        } else {
            diagnostic = String(describing: lastError)
        }

        throw MLXBackendError.invalidStructuredOutput(diagnostic)
    }

    /// Eagerly load the model. Throws if weights are not installed.
    public func loadModel() async throws {
        guard !isModelLoaded else { return }

        guard let modelURL = await modelManager.installedURL() else {
            throw MLXBackendError.modelNotInstalled
        }

        let start = ContinuousClock.now
        do {
            try await runner.load(from: modelURL)
        } catch {
            throw MLXBackendError.modelLoadFailed(error)
        }
        isModelLoaded = true

        let elapsed = ContinuousClock.now - start
        Self.logger.info("Model loaded in \(elapsed)")
        latencyRecorder?.record(label: "modelLoad", duration: elapsed)
    }
}

public enum MLXBackendError: Error, Sendable {
    case modelNotInstalled
    case modelLoadFailed(any Error)
    case inferenceFailed(any Error)
    case invalidStructuredOutput(String)
}
