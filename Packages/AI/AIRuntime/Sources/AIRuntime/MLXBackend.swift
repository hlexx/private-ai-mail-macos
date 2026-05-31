import AIPrompts
import Foundation
import AppFoundation

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
        maxRetries: Int = 2,
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
        try await runStructuredTask(
            ThreadBriefTask.self,
            input: ThreadBriefTaskInput(messages: messages, attachments: attachments),
            label: "threadBrief"
        )
    }

    /// Generate a draft reply from thread messages.
    public func draftReply(
        messages: [PromptMessage],
        tone: String,
        replyLanguage: String
    ) async throws -> ParsedThreadReply {
        try await runStructuredTask(
            DraftReplyTask.self,
            input: DraftReplyTaskInput(messages: messages, tone: tone, replyLanguage: replyLanguage),
            label: "draftReply"
        )
    }

    /// Generate an attachment summary from extracted chunks.
    public func attachmentSummary(
        filename: String,
        mime: String,
        chunks: [PromptAttachmentChunk]
    ) async throws -> ParsedAttachmentSummary {
        try await runStructuredTask(
            AttachmentSummaryTask.self,
            input: AttachmentSummaryTaskInput(filename: filename, mime: mime, chunks: chunks),
            label: "attachmentSummary"
        )
    }

    private func runStructuredTask<TaskDefinition: PromptTaskDefinition>(
        _ task: TaskDefinition.Type,
        input: TaskDefinition.Input,
        label: String
    ) async throws -> TaskDefinition.Output {
        try Task.checkCancellation()

        let systemPrompt = task.systemPrompt
        let userPrompt = task.renderUserPrompt(input)
        let taskMaxOutputTokens = min(maxOutputTokens, task.metadata.maxOutputTokens)

        let start = ContinuousClock.now
        var lastError: (any Error)?

        for attempt in 0 ... maxRetries {
            try Task.checkCancellation()

            do {
                let rawOutput = try await runner.generate(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: taskMaxOutputTokens,
                    responsePrefix: task.outputSeed,
                    onToken: { _ in }
                )

                let parsed = try task.parse(rawOutput)

                let elapsed = ContinuousClock.now - start
                Self.logAITask(
                    operation: label,
                    status: "generated",
                    duration: elapsed,
                    retryNumber: attempt + 1,
                    schemaVersion: task.metadata.schemaVersion
                )
                latencyRecorder?.record(label: label, duration: elapsed)

                return parsed
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if !Self.isParseError(error) {
                    throw MLXBackendError.inferenceFailed(error)
                }
                if attempt < maxRetries {
                    Self.logAITask(
                        operation: label,
                        status: "retrying",
                        severity: .warning,
                        retryNumber: attempt + 1,
                        schemaVersion: task.metadata.schemaVersion,
                        errorCategory: "invalid_structured_output"
                    )
                    continue
                }
            }
        }

        let diagnostic = Self.parseDiagnostic(lastError)

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
        Self.logAITask(operation: "model_load", status: "loaded", duration: elapsed)
        latencyRecorder?.record(label: "modelLoad", duration: elapsed)
    }

    private static func isParseError(_ error: any Error) -> Bool {
        error is ThreadBriefParser.ParseError
            || error is DraftReplyParser.ParseError
            || error is AttachmentSummaryParser.ParseError
            || error is PromptParseError
    }

    private static func parseDiagnostic(_ error: (any Error)?) -> String {
        if let parseError = error as? ThreadBriefParser.ParseError {
            switch parseError {
            case .invalidJSON(let raw): return raw
            case .schemaViolation(let msg): return msg
            }
        }
        if let parseError = error as? DraftReplyParser.ParseError {
            switch parseError {
            case .invalidJSON(let raw): return raw
            case .schemaViolation(let msg): return msg
            }
        }
        if let parseError = error as? AttachmentSummaryParser.ParseError {
            switch parseError {
            case .invalidJSON(let raw): return raw
            case .schemaViolation(let msg): return msg
            }
        }
        if let parseError = error as? PromptParseError {
            switch parseError {
            case .invalidJSON(let raw): return raw
            case .schemaViolation(let msg): return msg
            }
        }
        return String(describing: error)
    }

    private static func logAITask(
        operation: String,
        status: String,
        severity: PrivacyObservabilitySeverity = .info,
        duration: Duration? = nil,
        retryNumber: Int? = nil,
        schemaVersion: String? = nil,
        errorCategory: String? = nil
    ) {
        var fields: [PrivacyObservabilityField: String] = [
            .operation: operation,
            .status: status
        ]
        if let duration {
            fields[.durationMilliseconds] = PrivacyObservability.durationMillisecondsString(duration)
        }
        if let retryNumber {
            fields[.retryNumber] = "\(retryNumber)"
        }
        if let schemaVersion {
            fields[.schemaVersion] = schemaVersion
        }
        if let errorCategory {
            fields[.errorCategory] = errorCategory
        }
        PrivacyObservability.log(
            PrivacyObservabilityEvent(category: .ai, name: "ai.runtime", fields: fields),
            severity: severity
        )
    }
}

public enum MLXBackendError: Error, Sendable {
    case modelNotInstalled
    case modelLoadFailed(any Error)
    case inferenceFailed(any Error)
    case invalidStructuredOutput(String)
}
