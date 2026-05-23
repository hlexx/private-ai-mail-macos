import AttachmentKit
import Foundation

public struct AttachmentSummaryKeyField: Codable, Equatable, Sendable {
    public var label: String
    public var value: String
    public var evidenceChunkIds: [String]

    public init(label: String, value: String, evidenceChunkIds: [String]) {
        self.label = label
        self.value = value
        self.evidenceChunkIds = evidenceChunkIds
    }
}

public struct AttachmentSummaryFinding: Codable, Equatable, Sendable {
    public var text: String
    public var evidenceChunkIds: [String]

    public init(text: String, evidenceChunkIds: [String]) {
        self.text = text
        self.evidenceChunkIds = evidenceChunkIds
    }
}

public struct AttachmentSummaryOutput: Codable, Equatable, Sendable {
    public var summary: String
    public var keyFields: [AttachmentSummaryKeyField]
    public var risks: [AttachmentSummaryFinding]
    public var nextSteps: [AttachmentSummaryFinding]
    public var evidenceChunkIds: [String]
    public var modelId: String
    public var promptVersion: String
    public var confidence: Double

    public init(
        summary: String,
        keyFields: [AttachmentSummaryKeyField],
        risks: [AttachmentSummaryFinding],
        nextSteps: [AttachmentSummaryFinding],
        evidenceChunkIds: [String],
        modelId: String,
        promptVersion: String,
        confidence: Double
    ) {
        precondition(confidence >= 0 && confidence <= 1)
        self.summary = summary
        self.keyFields = keyFields
        self.risks = risks
        self.nextSteps = nextSteps
        self.evidenceChunkIds = evidenceChunkIds
        self.modelId = modelId
        self.promptVersion = promptVersion
        self.confidence = confidence
    }
}

public enum AttachmentSummarySource: String, Codable, Equatable, Sendable {
    case cached
    case generated
}

public enum AttachmentSummaryIncompleteReason: String, Codable, Equatable, Sendable {
    case extractionIncomplete
    case noExtractableText
    case noRelevantChunks
}

public enum AttachmentSummaryUnsupportedReason: String, Codable, Equatable, Sendable {
    case unsupportedExtraction
}

public enum AttachmentSummaryFailureCode: String, Codable, Equatable, Sendable {
    case extractionFailed
    case cacheReadFailed
    case cacheWriteFailed
    case artifactEncodingFailed
    case artifactDecodingFailed
    case summarizerFailed
    case cloudFallbackNotConfigured
}

public struct AttachmentSummaryFailure: Equatable, Sendable {
    public var code: AttachmentSummaryFailureCode
    public var message: String

    public init(code: AttachmentSummaryFailureCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum AttachmentSummaryStatus: Equatable, Sendable {
    case complete(AttachmentSummaryOutput, source: AttachmentSummarySource)
    case incomplete(AttachmentSummaryOutput?, reason: AttachmentSummaryIncompleteReason, source: AttachmentSummarySource?)
    case unsupported(AttachmentSummaryUnsupportedReason)
    case failed(AttachmentSummaryFailure)
}

public struct AttachmentSummaryRequest: Equatable, Sendable {
    public static let defaultQueryText = "summary key fields risks next steps deadline total amount invoice due date action"

    public var scope: AttachmentRAGCacheScope
    public var extractionVersion: String
    public var extractionResult: AttachmentExtractionResult
    public var query: AttachmentRetrievalQuery
    public var createdAt: Int

    public init(
        scope: AttachmentRAGCacheScope,
        extractionVersion: String,
        extractionResult: AttachmentExtractionResult,
        query: AttachmentRetrievalQuery? = nil,
        createdAt: Int
    ) {
        self.scope = scope
        self.extractionVersion = extractionVersion
        self.extractionResult = extractionResult
        self.query = query ?? AttachmentRetrievalQuery(text: Self.defaultQueryText, limit: 8)
        self.createdAt = createdAt
    }
}

public struct AttachmentSummaryInput: Equatable, Sendable {
    public var scope: AttachmentRAGCacheScope
    public var extractionStatus: AttachmentExtractionStatus
    public var query: AttachmentRetrievalQuery
    public var chunks: [AttachmentChunk]

    public init(
        scope: AttachmentRAGCacheScope,
        extractionStatus: AttachmentExtractionStatus,
        query: AttachmentRetrievalQuery,
        chunks: [AttachmentChunk]
    ) {
        self.scope = scope
        self.extractionStatus = extractionStatus
        self.query = query
        self.chunks = chunks
    }
}

public protocol AttachmentSummarizer: Sendable {
    var modelId: String { get }
    var promptVersion: String { get }

    func summarize(_ input: AttachmentSummaryInput) async throws -> AttachmentSummaryOutput
}

public enum AttachmentSummarizerError: Error, Equatable, Sendable {
    case noEvidenceChunks
}

public struct DeterministicAttachmentSummarizer: AttachmentSummarizer {
    public var modelId: String
    public var promptVersion: String

    public init(
        modelId: String = "local-deterministic-attachment-summary",
        promptVersion: String = "attachment-summary-prompt-v1"
    ) {
        self.modelId = modelId
        self.promptVersion = promptVersion
    }

    public func summarize(_ input: AttachmentSummaryInput) async throws -> AttachmentSummaryOutput {
        guard !input.chunks.isEmpty else {
            throw AttachmentSummarizerError.noEvidenceChunks
        }

        let evidenceChunkIds = input.chunks.map(\.id)
        let combinedText = normalizedSummaryText(input.chunks.map(\.text).joined(separator: " "))
        let summary = summarySnippet(from: combinedText)
        let keyFields = deterministicKeyFields(from: input.chunks)
        let risks = deterministicRisks(from: input.chunks)
        let nextSteps = deterministicNextSteps(from: input.chunks)
        let confidence = input.extractionStatus == .complete ? 0.78 : 0.56

        return AttachmentSummaryOutput(
            summary: summary,
            keyFields: keyFields,
            risks: risks,
            nextSteps: nextSteps,
            evidenceChunkIds: evidenceChunkIds,
            modelId: modelId,
            promptVersion: promptVersion,
            confidence: confidence
        )
    }
}

public struct AttachmentSummaryOrchestrator: Sendable {
    private let cache: any AttachmentRAGCache
    private let chunker: LocalAttachmentChunker
    private let retriever: LocalAttachmentRetriever
    private let summarizer: (any AttachmentSummarizer)?

    public init(
        cache: any AttachmentRAGCache,
        chunker: LocalAttachmentChunker = LocalAttachmentChunker(),
        retriever: LocalAttachmentRetriever = LocalAttachmentRetriever(),
        summarizer: (any AttachmentSummarizer)? = DeterministicAttachmentSummarizer()
    ) {
        self.cache = cache
        self.chunker = chunker
        self.retriever = retriever
        self.summarizer = summarizer
    }

    public func summarize(_ request: AttachmentSummaryRequest) async -> AttachmentSummaryStatus {
        switch request.extractionResult.status {
        case .unsupported:
            return .unsupported(.unsupportedExtraction)
        case .failed:
            return .failed(AttachmentSummaryFailure(
                code: .extractionFailed,
                message: "Attachment extraction failed; summary generation is not attempted."
            ))
        case .complete, .incomplete:
            break
        }

        guard let summarizer else {
            return .failed(AttachmentSummaryFailure(
                code: .cloudFallbackNotConfigured,
                message: "No local attachment summarizer is configured, and cloud fallback is disabled."
            ))
        }

        let artifactKey = AttachmentAIArtifactCacheKey(
            scope: request.scope,
            chunkingPolicyVersion: chunker.policy.version,
            modelId: summarizer.modelId,
            promptVersion: summarizer.promptVersion
        )

        do {
            if let cached = try cache.fetchArtifact(for: artifactKey) {
                let output = try decodeSummaryOutput(cached.payloadJSON)
                return status(
                    for: request.extractionResult.status,
                    output: output,
                    source: .cached
                )
            }
        } catch is DecodingError {
            return .failed(AttachmentSummaryFailure(
                code: .artifactDecodingFailed,
                message: "Cached attachment summary artifact could not be decoded."
            ))
        } catch {
            return .failed(AttachmentSummaryFailure(
                code: .cacheReadFailed,
                message: "Attachment summary cache read failed: \(String(describing: error))"
            ))
        }

        let chunks: [AttachmentChunk]
        do {
            if let cachedChunks = try cache.fetchChunks(
                for: request.scope,
                policyVersion: chunker.policy.version
            ) {
                chunks = cachedChunks
            } else {
                let generatedChunks = chunker.chunks(for: AttachmentChunkingInput(
                    attachmentId: request.scope.attachmentId,
                    extractionVersion: request.extractionVersion,
                    extractionResult: request.extractionResult
                ))
                guard !generatedChunks.isEmpty else {
                    return .incomplete(nil, reason: .noExtractableText, source: nil)
                }

                do {
                    try cache.upsertChunks(generatedChunks, for: request.scope, createdAt: request.createdAt)
                } catch {
                    return .failed(AttachmentSummaryFailure(
                        code: .cacheWriteFailed,
                        message: "Attachment chunk cache write failed: \(String(describing: error))"
                    ))
                }
                chunks = generatedChunks
            }
        } catch {
            return .failed(AttachmentSummaryFailure(
                code: .cacheReadFailed,
                message: "Attachment chunk cache read failed: \(String(describing: error))"
            ))
        }

        let relevantChunks = retriever
            .retrieve(request.query, from: chunks)
            .map(\.chunk)

        guard !relevantChunks.isEmpty else {
            return .incomplete(nil, reason: .noRelevantChunks, source: nil)
        }

        let output: AttachmentSummaryOutput
        do {
            output = try await summarizer.summarize(AttachmentSummaryInput(
                scope: request.scope,
                extractionStatus: request.extractionResult.status,
                query: request.query,
                chunks: relevantChunks
            ))
        } catch {
            return .failed(AttachmentSummaryFailure(
                code: .summarizerFailed,
                message: "Attachment summarizer failed: \(String(describing: error))"
            ))
        }

        do {
            let payloadJSON = try encodeSummaryOutput(output)
            try cache.upsertArtifact(AttachmentCachedAIArtifact(
                key: artifactKey,
                payloadJSON: payloadJSON,
                createdAt: request.createdAt,
                updatedAt: request.createdAt
            ))
        } catch is EncodingError {
            return .failed(AttachmentSummaryFailure(
                code: .artifactEncodingFailed,
                message: "Attachment summary artifact could not be encoded."
            ))
        } catch {
            return .failed(AttachmentSummaryFailure(
                code: .cacheWriteFailed,
                message: "Attachment summary cache write failed: \(String(describing: error))"
            ))
        }

        return status(
            for: request.extractionResult.status,
            output: output,
            source: .generated
        )
    }

    private func status(
        for extractionStatus: AttachmentExtractionStatus,
        output: AttachmentSummaryOutput,
        source: AttachmentSummarySource
    ) -> AttachmentSummaryStatus {
        if extractionStatus == .incomplete {
            return .incomplete(output, reason: .extractionIncomplete, source: source)
        }
        return .complete(output, source: source)
    }
}

private func encodeSummaryOutput(_ output: AttachmentSummaryOutput) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(output)
    return String(decoding: data, as: UTF8.self)
}

private func decodeSummaryOutput(_ payloadJSON: String) throws -> AttachmentSummaryOutput {
    let data = Data(payloadJSON.utf8)
    return try JSONDecoder().decode(AttachmentSummaryOutput.self, from: data)
}

private func normalizedSummaryText(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func summarySnippet(from text: String) -> String {
    guard !text.isEmpty else {
        return "No extractable attachment text."
    }

    let maxCharacters = 220
    guard text.count > maxCharacters else {
        return text
    }

    let end = text.index(text.startIndex, offsetBy: maxCharacters)
    return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func deterministicKeyFields(from chunks: [AttachmentChunk]) -> [AttachmentSummaryKeyField] {
    var fields: [AttachmentSummaryKeyField] = []
    var seen = Set<String>()

    for chunk in chunks {
        for line in chunk.text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let candidate: (String, String)?
            if let separator = trimmed.firstIndex(of: ":") {
                let label = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                candidate = label.isEmpty || value.isEmpty ? nil : (String(label), String(value))
            } else {
                candidate = inferredKeyField(from: trimmed)
            }

            guard let candidate else { continue }

            let key = "\(candidate.0.lowercased())=\(candidate.1.lowercased())"
            guard seen.insert(key).inserted else { continue }

            fields.append(AttachmentSummaryKeyField(
                label: candidate.0,
                value: candidate.1,
                evidenceChunkIds: [chunk.id]
            ))

            if fields.count == 6 {
                return fields
            }
        }
    }

    return fields
}

private func inferredKeyField(from text: String) -> (String, String)? {
    let lowercased = text.lowercased()
    if lowercased.contains("invoice") {
        return ("invoice", text)
    }
    if lowercased.contains("total") || lowercased.contains("amount") {
        return ("amount", text)
    }
    if lowercased.contains("due") || lowercased.contains("deadline") {
        return ("deadline", text)
    }
    return nil
}

private func deterministicRisks(from chunks: [AttachmentChunk]) -> [AttachmentSummaryFinding] {
    let riskTerms = ["risk", "overdue", "penalty", "urgent", "late", "failed"]
    return deterministicFindings(
        from: chunks,
        matching: riskTerms,
        fallback: nil,
        limit: 4
    )
}

private func deterministicNextSteps(from chunks: [AttachmentChunk]) -> [AttachmentSummaryFinding] {
    let actionTerms = ["due", "deadline", "pay", "approve", "sign", "reply", "action"]
    let findings = deterministicFindings(
        from: chunks,
        matching: actionTerms,
        fallback: nil,
        limit: 4
    )

    guard findings.isEmpty else {
        return findings
    }

    return [
        AttachmentSummaryFinding(
            text: "Review the attachment details before replying.",
            evidenceChunkIds: chunks.prefix(1).map(\.id)
        ),
    ]
}

private func deterministicFindings(
    from chunks: [AttachmentChunk],
    matching terms: [String],
    fallback: String?,
    limit: Int
) -> [AttachmentSummaryFinding] {
    var findings: [AttachmentSummaryFinding] = []
    var seen = Set<String>()

    for chunk in chunks {
        let normalized = normalizedSummaryText(chunk.text)
        let lowercased = normalized.lowercased()
        guard terms.contains(where: lowercased.contains) else { continue }
        guard seen.insert(lowercased).inserted else { continue }

        findings.append(AttachmentSummaryFinding(
            text: summarySnippet(from: normalized),
            evidenceChunkIds: [chunk.id]
        ))

        if findings.count == limit {
            return findings
        }
    }

    if findings.isEmpty, let fallback {
        return [AttachmentSummaryFinding(text: fallback, evidenceChunkIds: [])]
    }
    return findings
}
