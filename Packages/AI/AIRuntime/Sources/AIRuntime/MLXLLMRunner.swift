import Foundation
import MLX
import MLXLLM
import MLXLMCommon
@preconcurrency import Tokenizers

/// Real LLM runner backed by Apple MLX.
/// Loads Gemma weights via MLX and runs autoregressive decoding on the GPU.
final class MLXLLMRunner: LLMRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _isLoaded = false
    private var _modelContainer: ModelContainer?

    var isLoaded: Bool {
        lock.withLock { _isLoaded }
    }

    func load(from modelDirectory: URL) async throws {
        let alreadyLoaded = lock.withLock { _isLoaded }
        guard !alreadyLoaded else { return }

        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: TransformersTokenizerLoader()
            )
            lock.withLock {
                self._modelContainer = container
                self._isLoaded = true
            }
        } catch {
            throw MLXLLMRunnerError.weightLoadFailed(String(describing: error))
        }
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        onToken: @Sendable (String) -> Void
    ) async throws -> String {
        guard let container = lock.withLock({ _modelContainer }) else {
            throw MLXLLMRunnerError.modelNotLoaded
        }

        // Tokenize prompt directly to bypass the Jinja chat template parser
        // (swift-transformers' Jinja parser doesn't support the * operator
        // used in Gemma 4's chat_template.jinja).
        // Seed the model response with "{" so it starts generating JSON immediately
        // (critical for small models like E2B 1.21B that otherwise emit thinking tokens).
        let prompt = "<start_of_turn>user\n\(systemPrompt)\n\n\(userPrompt)<end_of_turn>\n<start_of_turn>model\n{"
        let tokens = try await container.perform { (_, tokenizer) in
            tokenizer.encode(text: prompt)
        }
        let input = LMInput(tokens: MLXArray(tokens))

        let effectiveMaxTokens = min(maxTokens, 256)
        let parameters = GenerateParameters(
            maxTokens: effectiveMaxTokens,
            temperature: 0.1,
            topP: 0.9
        )

        let stream = try await container.generate(
            input: input,
            parameters: parameters
        )

        // Prepend the seeded "{" to capture the full JSON object
        var fullOutput = "{"

        for await generation in stream {
            try Task.checkCancellation()

            switch generation {
            case .chunk(let text):
                fullOutput += text
                onToken(text)
            case .info:
                break
            case .toolCall:
                break
            }
        }

        return fullOutput
    }
}

/// Bridges swift-transformers' Tokenizer to MLXLMCommon.Tokenizer
/// and provides a TokenizerLoader for loading from local directories.
private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

struct TransformersTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

enum MLXLLMRunnerError: Error, Sendable {
    case modelNotLoaded
    case weightLoadFailed(String)
    case tokeniserMissing
    case nonJSONOutput(String)

    var isRetryable: Bool {
        switch self {
        case .nonJSONOutput: return true
        default: return false
        }
    }
}
