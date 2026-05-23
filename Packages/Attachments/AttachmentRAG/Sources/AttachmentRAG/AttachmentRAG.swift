import AttachmentKit
import CryptoKit
import Foundation

// MARK: - Public API

public enum AttachmentRAG {
    public static let moduleName = "AttachmentRAG"
}

public struct AttachmentChunk: Equatable, Sendable, Identifiable {
    public var id: String
    public var attachmentId: String
    public var extractionVersion: String
    public var policyVersion: String
    public var index: Int
    public var sourceIndex: Int
    public var text: String
    public var evidence: [AttachmentEvidenceSource]

    public init(
        id: String,
        attachmentId: String,
        extractionVersion: String,
        policyVersion: String,
        index: Int,
        sourceIndex: Int,
        text: String,
        evidence: [AttachmentEvidenceSource]
    ) {
        self.id = id
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
        self.policyVersion = policyVersion
        self.index = index
        self.sourceIndex = sourceIndex
        self.text = text
        self.evidence = evidence
    }
}

public enum AttachmentEvidenceSource: Equatable, Sendable {
    case page(number: Int)
    case byteRange(start: Int, end: Int)
    case section(name: String)
    case imageRegion(x: Double, y: Double, width: Double, height: Double, confidence: Float)

    public init(locator: AttachmentEvidenceLocator) {
        switch locator {
        case let .page(number):
            self = .page(number: number)
        case let .byteRange(start, end):
            self = .byteRange(start: start, end: end)
        case let .section(name):
            self = .section(name: name)
        case let .imageRegion(region, confidence):
            self = .imageRegion(
                x: region.x,
                y: region.y,
                width: region.width,
                height: region.height,
                confidence: confidence
            )
        }
    }
}

public struct AttachmentChunkingPolicy: Equatable, Sendable {
    public static let `default` = AttachmentChunkingPolicy(
        version: "attachment-rag-chunking-v1",
        maxCharacters: 1_200,
        overlapCharacters: 120
    )

    public var version: String
    public var maxCharacters: Int
    public var overlapCharacters: Int

    public init(version: String, maxCharacters: Int, overlapCharacters: Int = 0) {
        precondition(!version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        precondition(maxCharacters > 0)
        precondition(overlapCharacters >= 0)
        precondition(overlapCharacters < maxCharacters)
        self.version = version
        self.maxCharacters = maxCharacters
        self.overlapCharacters = overlapCharacters
    }
}

public struct AttachmentChunkingInput: Equatable, Sendable {
    public var attachmentId: String
    public var extractionVersion: String
    public var extractionResult: AttachmentExtractionResult

    public init(
        attachmentId: String,
        extractionVersion: String,
        extractionResult: AttachmentExtractionResult
    ) {
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
        self.extractionResult = extractionResult
    }
}

public struct AttachmentRetrievalQuery: Equatable, Sendable {
    public var text: String
    public var limit: Int
    public var minimumScore: Double

    public init(text: String, limit: Int = 5, minimumScore: Double = 0) {
        precondition(limit > 0)
        precondition(minimumScore >= 0)
        self.text = text
        self.limit = limit
        self.minimumScore = minimumScore
    }
}

public struct AttachmentRetrievalResult: Equatable, Sendable {
    public var chunk: AttachmentChunk
    public var score: Double
    public var matchedTerms: [String]

    public init(chunk: AttachmentChunk, score: Double, matchedTerms: [String]) {
        self.chunk = chunk
        self.score = score
        self.matchedTerms = matchedTerms
    }
}

public struct AttachmentChunkCacheKeyInput: Equatable, Sendable {
    public var attachmentId: String
    public var extractionVersion: String
    public var extractionContentHash: String
    public var chunkingPolicyVersion: String

    public init(
        attachmentId: String,
        extractionVersion: String,
        extractionContentHash: String,
        chunkingPolicyVersion: String
    ) {
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
        self.extractionContentHash = extractionContentHash
        self.chunkingPolicyVersion = chunkingPolicyVersion
    }

    public var cacheKey: String {
        let digest = stableDigest(lengthPrefixedFields([
            attachmentId,
            extractionVersion,
            extractionContentHash,
            chunkingPolicyVersion,
        ]))
        return "attachment-chunks:v1:\(digest)"
    }
}

// MARK: - Chunking

public struct LocalAttachmentChunker: Sendable {
    public var policy: AttachmentChunkingPolicy

    public init(policy: AttachmentChunkingPolicy = .default) {
        self.policy = policy
    }

    public func chunks(for input: AttachmentChunkingInput) -> [AttachmentChunk] {
        guard input.extractionResult.status != .unsupported,
              input.extractionResult.status != .failed else {
            return []
        }

        var chunks: [AttachmentChunk] = []
        for (sourceIndex, extracted) in input.extractionResult.extractedText.enumerated() {
            guard let trimmed = trimmedTextWithSourceOffsets(extracted.text) else {
                continue
            }

            let evidence = AttachmentEvidenceSource(locator: extracted.locator)
            for range in chunkRanges(in: trimmed.text, policy: policy) {
                let chunkText = String(trimmed.text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !chunkText.isEmpty else { continue }

                let adjustedEvidence = evidence.adjusted(
                    forChunkRange: range,
                    inTrimmedText: trimmed.text,
                    sourceLeadingUTF8Offset: trimmed.leadingUTF8Offset
                )
                let index = chunks.count
                let id = makeChunkID(
                    attachmentId: input.attachmentId,
                    extractionVersion: input.extractionVersion,
                    policyVersion: policy.version,
                    index: index,
                    sourceIndex: sourceIndex,
                    evidence: adjustedEvidence,
                    text: chunkText
                )

                chunks.append(
                    AttachmentChunk(
                        id: id,
                        attachmentId: input.attachmentId,
                        extractionVersion: input.extractionVersion,
                        policyVersion: policy.version,
                        index: index,
                        sourceIndex: sourceIndex,
                        text: chunkText,
                        evidence: [adjustedEvidence]
                    )
                )
            }
        }
        return chunks
    }
}

// MARK: - Retrieval

public struct LocalAttachmentRetriever: Sendable {
    public init() {}

    public func retrieve(
        _ query: AttachmentRetrievalQuery,
        from chunks: [AttachmentChunk]
    ) -> [AttachmentRetrievalResult] {
        let queryTerms = orderedUnique(tokenize(query.text))
        guard !queryTerms.isEmpty else { return [] }

        return chunks.compactMap { chunk in
            let chunkTerms = tokenize(chunk.text)
            guard !chunkTerms.isEmpty else { return nil }

            let frequencies = Dictionary(grouping: chunkTerms, by: { $0 })
                .mapValues(\.count)
            var matchedTerms: [String] = []
            var score = 0.0
            for term in queryTerms {
                guard let frequency = frequencies[term], frequency > 0 else {
                    continue
                }
                matchedTerms.append(term)
                score += Double(frequency)
            }

            if matchedTerms.count > 1,
               normalizedPhrase(chunk.text).contains(normalizedPhrase(query.text)) {
                score += Double(matchedTerms.count)
            }

            guard score >= query.minimumScore, score > 0 else {
                return nil
            }
            return AttachmentRetrievalResult(chunk: chunk, score: score, matchedTerms: matchedTerms)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.chunk.index != rhs.chunk.index {
                return lhs.chunk.index < rhs.chunk.index
            }
            return lhs.chunk.id < rhs.chunk.id
        }
        .prefix(query.limit)
        .map { $0 }
    }
}

// MARK: - Private Helpers

private struct TrimmedText {
    var text: String
    var leadingUTF8Offset: Int
}

private func trimmedTextWithSourceOffsets(_ text: String) -> TrimmedText? {
    guard let firstContent = text.firstIndex(where: { !$0.isWhitespace }),
          let lastContent = text.lastIndex(where: { !$0.isWhitespace }) else {
        return nil
    }

    let upperBound = text.index(after: lastContent)
    return TrimmedText(
        text: String(text[firstContent..<upperBound]),
        leadingUTF8Offset: text[..<firstContent].utf8.count
    )
}

private func chunkRanges(
    in text: String,
    policy: AttachmentChunkingPolicy
) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    var start = text.startIndex

    while start < text.endIndex {
        let hardEnd = text.index(start, offsetBy: policy.maxCharacters, limitedBy: text.endIndex) ?? text.endIndex
        let end = hardEnd == text.endIndex
            ? hardEnd
            : preferredBreak(in: text, from: start, through: hardEnd, minimumCharacters: policy.maxCharacters / 2)
        let trimmedRange = trim(text, range: start..<end)
        if !trimmedRange.isEmpty {
            ranges.append(trimmedRange)
        }

        guard end < text.endIndex else {
            break
        }

        let nextStart: String.Index
        if policy.overlapCharacters == 0 {
            nextStart = skipLeadingWhitespace(in: text, from: end)
        } else {
            let overlappedStart = text.index(
                end,
                offsetBy: -policy.overlapCharacters,
                limitedBy: start
            ) ?? start
            nextStart = skipLeadingWhitespace(in: text, from: overlappedStart)
        }

        start = nextStart > start ? nextStart : end
    }

    return ranges
}

private func preferredBreak(
    in text: String,
    from start: String.Index,
    through hardEnd: String.Index,
    minimumCharacters: Int
) -> String.Index {
    var cursor = hardEnd
    let minimumEnd = text.index(start, offsetBy: max(1, minimumCharacters), limitedBy: hardEnd) ?? hardEnd

    while cursor > minimumEnd {
        let previous = text.index(before: cursor)
        if text[previous].isWhitespace {
            return cursor
        }
        cursor = previous
    }

    return hardEnd
}

private func trim(_ text: String, range: Range<String.Index>) -> Range<String.Index> {
    var lower = range.lowerBound
    var upper = range.upperBound

    while lower < upper, text[lower].isWhitespace {
        lower = text.index(after: lower)
    }

    while upper > lower {
        let previous = text.index(before: upper)
        guard text[previous].isWhitespace else {
            break
        }
        upper = previous
    }

    return lower..<upper
}

private func skipLeadingWhitespace(in text: String, from index: String.Index) -> String.Index {
    var cursor = index
    while cursor < text.endIndex, text[cursor].isWhitespace {
        cursor = text.index(after: cursor)
    }
    return cursor
}

private func makeChunkID(
    attachmentId: String,
    extractionVersion: String,
    policyVersion: String,
    index: Int,
    sourceIndex: Int,
    evidence: AttachmentEvidenceSource,
    text: String
) -> String {
    let canonical = lengthPrefixedFields([
        attachmentId,
        extractionVersion,
        policyVersion,
        String(index),
        String(sourceIndex),
        evidence.canonicalValue,
        stableDigest(text),
    ])
    return "chunk:\(stableDigest(canonical))"
}

private func tokenize(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""

    for scalar in text.lowercased().unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            current.unicodeScalars.append(scalar)
        } else if !current.isEmpty {
            tokens.append(current)
            current.removeAll(keepingCapacity: true)
        }
    }

    if !current.isEmpty {
        tokens.append(current)
    }
    return tokens
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values where seen.insert(value).inserted {
        ordered.append(value)
    }
    return ordered
}

private func normalizedPhrase(_ text: String) -> String {
    tokenize(text).joined(separator: " ")
}

private func lengthPrefixedFields(_ fields: [String]) -> String {
    fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
}

private func stableDigest(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private extension AttachmentEvidenceSource {
    func adjusted(
        forChunkRange range: Range<String.Index>,
        inTrimmedText text: String,
        sourceLeadingUTF8Offset: Int
    ) -> AttachmentEvidenceSource {
        switch self {
        case let .byteRange(start, end):
            let chunkStart = sourceLeadingUTF8Offset + text[..<range.lowerBound].utf8.count
            let chunkEnd = sourceLeadingUTF8Offset + text[..<range.upperBound].utf8.count
            return .byteRange(start: start + chunkStart, end: min(end, start + chunkEnd))
        case .page, .section, .imageRegion:
            return self
        }
    }

    var canonicalValue: String {
        switch self {
        case let .page(number):
            return "page:\(number)"
        case let .byteRange(start, end):
            return "byte:\(start):\(end)"
        case let .section(name):
            return "section:\(name)"
        case let .imageRegion(x, y, width, height, confidence):
            return "image:\(x):\(y):\(width):\(height):\(confidence)"
        }
    }
}
