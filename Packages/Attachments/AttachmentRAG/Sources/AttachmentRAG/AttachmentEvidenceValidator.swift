import AIKit
import AIPrompts

enum AttachmentEvidenceValidationFailure: String {
    case missingEvidence
    case missingChunk
    case emptyQuote
    case quoteNotFound
}

enum AttachmentEvidenceValidator {
    static func validate(
        _ evidence: [AIAttachmentEvidence],
        chunks: [PromptAttachmentChunk]
    ) -> AttachmentEvidenceValidationFailure? {
        if !chunks.isEmpty, evidence.isEmpty {
            return .missingEvidence
        }

        let chunksByIndex = Dictionary(uniqueKeysWithValues: chunks.map { ($0.index, $0.text) })

        for item in evidence {
            guard let chunkText = chunksByIndex[item.chunkIndex] else {
                return .missingChunk
            }

            let quote = normalizedEvidenceText(item.quote)
            guard !quote.isEmpty else {
                return .emptyQuote
            }

            let normalizedChunk = normalizedEvidenceText(chunkText)
            guard normalizedChunk.contains(quote) else {
                return .quoteNotFound
            }
        }

        return nil
    }

    private static func normalizedEvidenceText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
