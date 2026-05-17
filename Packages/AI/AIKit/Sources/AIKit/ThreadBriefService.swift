import AIPrompts
import AIRuntime
import Foundation

/// Default `AIService` implementation that delegates thread brief generation
/// and reply drafting to an `MLXBackend`. The indirection supports future
/// routing to alternative backends (FoundationModels, llama.cpp).
public struct ThreadBriefService: AIService, Sendable {
    private let backend: MLXBackend

    public init(backend: MLXBackend) {
        self.backend = backend
    }

    public func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        let messages = input.messages.map { msg in
            PromptMessage(from: msg.from, sentAt: msg.sentAt, bodyText: msg.bodyText)
        }
        let attachments = input.attachments.map { att in
            PromptAttachment(filename: att.filename, mime: att.mime, pageCount: att.pageCount)
        }

        do {
            try await backend.loadModel()
        } catch let error as MLXBackendError {
            throw error.toAIError()
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.modelLoadFailed(error)
        }

        let parsed: ParsedThreadBrief
        do {
            parsed = try await backend.threadBrief(messages: messages, attachments: attachments)
        } catch let error as MLXBackendError {
            throw error.toAIError()
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.inferenceFailed(error)
        }

        return AIThreadBrief(
            summary: parsed.summary,
            request: parsed.request,
            deadline: parsed.deadline,
            risk: parsed.risk,
            nextStep: parsed.nextStep,
            evidence: parsed.evidence,
            confidence: parsed.confidence
        )
    }

    public func draftReply(
        _ input: AIThreadInput,
        tone: AIReplyTone,
        locale: Locale,
        replyLanguage: String?
    ) async throws -> AIThreadReply {
        let messages = input.messages.map { msg in
            PromptMessage(from: msg.from, sentAt: msg.sentAt, bodyText: msg.bodyText)
        }

        do {
            try await backend.loadModel()
        } catch let error as MLXBackendError {
            throw error.toAIError()
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.modelLoadFailed(error)
        }

        let parsed: ParsedThreadReply
        do {
            parsed = try await backend.draftReply(
                messages: messages,
                tone: tone.rawValue,
                replyLanguage: replyLanguage ?? locale.language.languageCode?.identifier ?? "en"
            )
        } catch let error as MLXBackendError {
            throw error.toAIError()
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.inferenceFailed(error)
        }

        return AIThreadReply(
            body: parsed.body,
            evidenceMessageIDs: parsed.evidenceMessageIDs,
            detectedReplyLanguage: parsed.detectedReplyLanguage,
            confidence: parsed.confidence
        )
    }

    /// Build a live `AIService` backed by MLX inference.
    public static func live(modelManager: ModelManager) -> any AIService {
        let backend = MLXBackend(modelManager: modelManager)
        return ThreadBriefService(backend: backend)
    }
}

// MARK: - Error Mapping

extension MLXBackendError {
    func toAIError() -> AIError {
        switch self {
        case .modelNotInstalled:
            return .modelNotInstalled
        case .modelLoadFailed(let error):
            return .modelLoadFailed(error)
        case .inferenceFailed(let error):
            return .inferenceFailed(error)
        case .invalidStructuredOutput(let diagnostic):
            return .invalidStructuredOutput(diagnostic)
        }
    }
}
