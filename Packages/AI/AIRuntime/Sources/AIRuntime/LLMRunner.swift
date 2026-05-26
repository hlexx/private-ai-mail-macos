import Foundation

/// Abstraction over the LLM inference engine.
/// The real implementation wraps MLX; tests inject a `FakeLLMRunner`.
protocol LLMRunner: Sendable {
    /// Load model weights from the given directory. Called once, lazily.
    func load(from modelDirectory: URL) async throws

    /// Generate text from system + user prompts, streaming tokens.
    /// `onToken` is called for each decoded token. The runner MUST check
    /// `Task.isCancelled` between tokens and throw `CancellationError` if set.
    /// Returns the full generated string when done or when `maxTokens` is reached.
    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        responsePrefix: String,
        onToken: @Sendable (String) -> Void
    ) async throws -> String
}
