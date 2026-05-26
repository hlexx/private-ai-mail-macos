import AIKit
import AIPrompts

extension AttachmentSummaryOrchestrator {
    public static func chunk(_ text: String, maxCharacters: Int) -> [PromptAttachmentChunk] {
        guard !text.isEmpty else { return [] }
        var chunks: [PromptAttachmentChunk] = []
        var start = text.startIndex
        var offset = 0
        var index = 0

        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxCharacters, limitedBy: text.endIndex) ?? text.endIndex
            let chunkText = String(text[start..<end])
            chunks.append(PromptAttachmentChunk(index: index, sourceOffset: offset, text: chunkText))
            offset += chunkText.count
            index += 1
            start = end
        }

        return chunks
    }

    static func validateSummaryEvidence(
        _ summary: AIAttachmentSummary,
        chunks: [PromptAttachmentChunk]
    ) throws {
        var chunksByIndex: [Int: String] = [:]
        for chunk in chunks {
            chunksByIndex[chunk.index] = normalizedEvidenceText(chunk.text)
        }

        for evidence in summary.evidence {
            let normalizedQuote = normalizedEvidenceText(evidence.quote)
            guard !normalizedQuote.isEmpty else {
                throw AttachmentSummaryEvidenceValidationError(kind: .emptyQuote)
            }
            guard let chunkText = chunksByIndex[evidence.chunkIndex] else {
                throw AttachmentSummaryEvidenceValidationError(kind: .missingChunk)
            }
            guard chunkText.contains(normalizedQuote) else {
                throw AttachmentSummaryEvidenceValidationError(kind: .quoteNotFound)
            }
        }
    }

    private static func normalizedEvidenceText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
