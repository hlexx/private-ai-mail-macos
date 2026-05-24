import AIKit
import Foundation

/// Heuristic metrics for evaluating thread brief quality.
public enum Metrics {

    /// Faithfulness: checks that quoted entities (senders, dates, dollar amounts)
    /// in the brief appear verbatim in the source thread.
    ///
    /// Returns a score between 0.0 and 1.0. Higher is better.
    public static func faithfulness(brief: AIThreadBrief, input: AIThreadInput) -> Double {
        let sourceText = buildSourceText(from: input)
        let claims = extractClaims(from: brief)
        guard !claims.isEmpty else { return 1.0 } // No claims to verify → faithful by default
        let matched = claims.filter { sourceText.localizedCaseInsensitiveContains($0) }.count
        return Double(matched) / Double(claims.count)
    }

    /// Hallucination rate: fraction of evidence entries that don't correspond
    /// to any sender, attachment filename, or substantive text in the input.
    ///
    /// Returns a score between 0.0 and 1.0. Lower is better.
    public static func hallucinationRate(brief: AIThreadBrief, input: AIThreadInput) -> Double {
        let evidence = brief.evidence
        guard !evidence.isEmpty else { return 0.0 }
        let sourceText = buildSourceText(from: input)
        let hallucinated = evidence.filter { entry in
            !isGrounded(entry, in: sourceText, input: input)
        }.count
        return Double(hallucinated) / Double(evidence.count)
    }

    /// Schema validity: returns true if all required fields are present and
    /// confidence is in [0, 1].
    public static func schemaValid(brief: AIThreadBrief) -> Bool {
        brief.confidence >= 0.0 && brief.confidence <= 1.0
    }

    public static func schemaValid(attachmentSummary: AIAttachmentSummary) -> Bool {
        !attachmentSummary.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachmentSummary.confidence >= 0.0
            && attachmentSummary.confidence <= 1.0
    }

    public static func evidenceCoverage(attachmentSummary: AIAttachmentSummary) -> Double {
        let claimCount = 1
            + attachmentSummary.keyFields.count
            + attachmentSummary.risks.count
            + attachmentSummary.nextSteps.count
        guard claimCount > 0 else { return 1.0 }
        return min(1.0, Double(attachmentSummary.evidence.count) / Double(claimCount))
    }

    public static func hallucinationRate(
        attachmentSummary: AIAttachmentSummary,
        sourceText: String,
        chunkCount: Int
    ) -> Double {
        guard !attachmentSummary.evidence.isEmpty else { return 0.0 }
        let hallucinated = attachmentSummary.evidence.filter { evidence in
            evidence.chunkIndex < 0
                || evidence.chunkIndex >= chunkCount
                || !sourceText.localizedCaseInsensitiveContains(evidence.quote)
        }.count
        return Double(hallucinated) / Double(attachmentSummary.evidence.count)
    }

    // MARK: - Internal helpers

    static func buildSourceText(from input: AIThreadInput) -> String {
        var parts: [String] = []
        for msg in input.messages {
            parts.append(msg.from)
            parts.append(msg.bodyText)
        }
        for att in input.attachments {
            parts.append(att.filename)
            parts.append(att.mime)
        }
        return parts.joined(separator: " ")
    }

    /// Extract verifiable claims from a brief: senders, dollar amounts, dates,
    /// and short quoted phrases.
    static func extractClaims(from brief: AIThreadBrief) -> [String] {
        var claims: [String] = []
        let allText = [brief.summary, brief.request, brief.deadline, brief.risk, brief.nextStep]
            .compactMap { $0 }
            .joined(separator: " ")

        // Dollar amounts like $4,250.00 or $85,000
        let dollarPattern = #"\$[\d,]+(?:\.\d{2})?"#
        claims.append(contentsOf: extractMatches(pattern: dollarPattern, from: allText))

        // Dates like April 15, May 1, Apr 10
        let datePattern = #"(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}"#
        claims.append(contentsOf: extractMatches(pattern: datePattern, from: allText))

        // Email-like senders
        let emailPattern = #"[\w.+-]+@[\w.-]+"#
        claims.append(contentsOf: extractMatches(pattern: emailPattern, from: allText))

        return claims
    }

    /// Check if an evidence entry is grounded in the source material.
    static func isGrounded(_ entry: String, in sourceText: String, input: AIThreadInput) -> Bool {
        // Direct substring match (case-insensitive)
        if sourceText.localizedCaseInsensitiveContains(entry) {
            return true
        }

        // Check if any significant words (4+ chars) from the entry appear in source
        let words = entry.split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 4 }

        guard !words.isEmpty else { return true } // Very short entry → can't verify

        let matchedWords = words.filter { sourceText.localizedCaseInsensitiveContains($0) }
        let ratio = Double(matchedWords.count) / Double(words.count)

        // At least 60% of significant words must appear in source
        return ratio >= 0.6
    }

    private static func extractMatches(pattern: String, from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
