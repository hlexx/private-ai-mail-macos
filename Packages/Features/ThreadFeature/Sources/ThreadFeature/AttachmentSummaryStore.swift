import AIKit
import AttachmentRAG
import Foundation
import Observation

public struct AttachmentSummaryViewData: Sendable, Equatable {
    public let summary: String
    public let keyFields: [AIKeyField]
    public let risks: [String]
    public let nextSteps: [String]
    public let evidence: [AIAttachmentEvidence]
    public let confidence: Double
    public let cached: Bool

    public init(summary: AIAttachmentSummary, cached: Bool) {
        self.summary = summary.summary
        self.keyFields = summary.keyFields
        self.risks = summary.risks
        self.nextSteps = summary.nextSteps
        self.evidence = summary.evidence
        self.confidence = summary.confidence
        self.cached = cached
    }
}

public enum AttachmentSummaryViewState: Sendable, Equatable {
    case idle
    case summarizing
    case summary(AttachmentSummaryViewData)
    case unsupported(String)
    case failed(String)

    public var isWorking: Bool {
        if case .summarizing = self { return true }
        return false
    }
}

@Observable
@MainActor
public final class AttachmentSummaryStore {
    public private(set) var states: [String: AttachmentSummaryViewState] = [:]
    private let orchestrator: AttachmentSummaryOrchestrator

    public init(orchestrator: AttachmentSummaryOrchestrator) {
        self.orchestrator = orchestrator
    }

    public func state(for attachment: AttachmentInfo) -> AttachmentSummaryViewState {
        states[key(for: attachment)] ?? .idle
    }

    public func summarize(_ attachment: AttachmentInfo) {
        let key = key(for: attachment)
        states[key] = .summarizing
        let request = AttachmentSummaryRequest(
            accountId: attachment.accountId,
            messageId: attachment.messageId,
            attachmentId: attachment.id,
            filename: attachment.filename,
            mime: attachment.mime ?? "application/octet-stream"
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await orchestrator.summarize(request)
                switch result {
                case .summary(let summary, let cached):
                    self.states[key] = .summary(.init(summary: summary, cached: cached))
                case .unsupported(let reason):
                    self.states[key] = .unsupported(reason)
                }
            } catch {
                self.states[key] = .failed(Self.userMessage(for: error))
            }
        }
    }

    private func key(for attachment: AttachmentInfo) -> String {
        "\(attachment.accountId):\(attachment.messageId):\(attachment.id)"
    }

    private static func userMessage(for error: any Error) -> String {
        if let ragError = error as? AttachmentRAGError {
            switch ragError {
            case .attachmentBytesUnavailable:
                return String(localized: "thread.attachment.summary.error.bytes", defaultValue: "Attachment data is not available yet.")
            case .extractedTextMissing:
                return String(localized: "thread.attachment.summary.error.empty", defaultValue: "No readable text was found.")
            case .invalidAttachmentSummaryEvidence:
                return String(localized: "thread.attachment.summary.error.evidence", defaultValue: "Summary evidence could not be verified.")
            }
        }
        return String(localized: "thread.attachment.summary.error.generic", defaultValue: "Could not summarize this attachment.")
    }
}
