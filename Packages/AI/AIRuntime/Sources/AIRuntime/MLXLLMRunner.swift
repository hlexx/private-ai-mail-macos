import Foundation
import MLX

/// Real LLM runner backed by Apple MLX.
/// Loads Gemma weights via MLX and runs autoregressive decoding on the GPU.
final class MLXLLMRunner: LLMRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var isLoaded = false
    private var modelDirectory: URL?

    func load(from modelDirectory: URL) async throws {
        let alreadyLoaded = lock.withLock { isLoaded }
        guard !alreadyLoaded else { return }
        // TODO: Load model weights and tokeniser from modelDirectory using MLX.
        // This requires mlx-swift-examples LLM utilities or a custom Gemma
        // model implementation. Deferred until integration testing with GPU.
        lock.withLock {
            self.modelDirectory = modelDirectory
            isLoaded = true
        }
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        onToken: @Sendable (String) -> Void
    ) async throws -> String {
        let loaded = lock.withLock { isLoaded }
        guard loaded else {
            throw MLXLLMRunnerError.modelNotLoaded
        }

        // TODO: Real MLX inference — tokenise, run forward pass, sample,
        // decode tokens, call onToken for each. Check Task.isCancelled
        // between tokens. Cap at maxTokens.
        //
        // Placeholder: this will be replaced with actual MLX calls once
        // the model loading pipeline is complete.
        throw MLXLLMRunnerError.notImplemented
    }
}

enum MLXLLMRunnerError: Error, Sendable {
    case modelNotLoaded
    case notImplemented
}
