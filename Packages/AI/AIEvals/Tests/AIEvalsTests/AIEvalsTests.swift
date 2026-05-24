import Foundation
import Testing
import AIKit
@testable import AIEvals

// MARK: - Metrics Tests

@Suite("Metrics")
struct MetricsTests {

    // MARK: - Faithfulness

    @Test func faithfulness_allClaimsPresent_returns1() {
        let input = AIThreadInput(messages: [
            .init(from: "alice@example.com", sentAt: .now, bodyText: "Invoice for $4,250.00 due April 15."),
        ])
        let brief = AIThreadBrief(
            summary: "Invoice for $4,250.00 due April 15",
            confidence: 0.9
        )
        let score = Metrics.faithfulness(brief: brief, input: input)
        #expect(score == 1.0)
    }

    @Test func faithfulness_noClaimsInBrief_returns1() {
        let input = AIThreadInput(messages: [
            .init(from: "bob@example.com", sentAt: .now, bodyText: "Just a quick update."),
        ])
        let brief = AIThreadBrief(
            summary: "Quick update received",
            confidence: 0.8
        )
        let score = Metrics.faithfulness(brief: brief, input: input)
        #expect(score == 1.0) // No extractable claims → faithful by default
    }

    @Test func faithfulness_dollarAmountMismatch_scoresLow() {
        let input = AIThreadInput(messages: [
            .init(from: "billing@example.com", sentAt: .now, bodyText: "Your bill is $100.00 for March."),
        ])
        let brief = AIThreadBrief(
            summary: "Bill for $500.00 in March",
            confidence: 0.7
        )
        let score = Metrics.faithfulness(brief: brief, input: input)
        #expect(score < 1.0)
    }

    @Test func faithfulness_mixedClaims_partialScore() {
        let input = AIThreadInput(messages: [
            .init(from: "hr@company.com", sentAt: .now, bodyText: "Offer: $85,000 salary, start May 1."),
        ])
        let brief = AIThreadBrief(
            summary: "Offer for $85,000 starting June 1",
            confidence: 0.8
        )
        // $85,000 present in source, but "June 1" doesn't match "May 1"
        let score = Metrics.faithfulness(brief: brief, input: input)
        #expect(score > 0.0)
        #expect(score < 1.0)
    }

    // MARK: - Hallucination Rate

    @Test func hallucinationRate_allEvidenceGrounded_returns0() {
        let input = AIThreadInput(messages: [
            .init(from: "pm@example.com", sentAt: .now, bodyText: "Meeting notes: launch date May 15, budget $45K approved."),
        ])
        let brief = AIThreadBrief(
            summary: "Meeting recap",
            evidence: ["launch date May 15", "budget $45K approved"],
            confidence: 0.9
        )
        let rate = Metrics.hallucinationRate(brief: brief, input: input)
        #expect(rate == 0.0)
    }

    @Test func hallucinationRate_noEvidence_returns0() {
        let input = AIThreadInput(messages: [
            .init(from: "test@example.com", sentAt: .now, bodyText: "Hello."),
        ])
        let brief = AIThreadBrief(summary: "Greeting", evidence: [], confidence: 0.5)
        let rate = Metrics.hallucinationRate(brief: brief, input: input)
        #expect(rate == 0.0)
    }

    @Test func hallucinationRate_allHallucinated_returns1() {
        let input = AIThreadInput(messages: [
            .init(from: "test@example.com", sentAt: .now, bodyText: "Simple update about project status."),
        ])
        let brief = AIThreadBrief(
            summary: "Update",
            evidence: ["quarterly earnings exceeded expectations significantly"],
            confidence: 0.5
        )
        let rate = Metrics.hallucinationRate(brief: brief, input: input)
        #expect(rate == 1.0)
    }

    @Test func hallucinationRate_partiallyGrounded_fractionalRate() {
        let input = AIThreadInput(messages: [
            .init(from: "pm@example.com", sentAt: .now,
                  bodyText: "API spec finalized. Database migration complete."),
        ])
        let brief = AIThreadBrief(
            summary: "Progress update",
            evidence: [
                "API spec finalized",             // grounded
                "frontend redesign completed",     // hallucinated
            ],
            confidence: 0.7
        )
        let rate = Metrics.hallucinationRate(brief: brief, input: input)
        #expect(rate == 0.5)
    }

    // MARK: - Schema Validity

    @Test func schemaValid_normalConfidence_returnsTrue() {
        let brief = AIThreadBrief(summary: "Test", confidence: 0.85)
        #expect(Metrics.schemaValid(brief: brief))
    }

    @Test func schemaValid_zeroConfidence_returnsTrue() {
        let brief = AIThreadBrief(confidence: 0.0)
        #expect(Metrics.schemaValid(brief: brief))
    }

    @Test func schemaValid_oneConfidence_returnsTrue() {
        let brief = AIThreadBrief(confidence: 1.0)
        #expect(Metrics.schemaValid(brief: brief))
    }

    @Test func schemaValid_negativeConfidence_returnsFalse() {
        let brief = AIThreadBrief(confidence: -0.1)
        #expect(!Metrics.schemaValid(brief: brief))
    }

    @Test func schemaValid_overOneConfidence_returnsFalse() {
        let brief = AIThreadBrief(confidence: 1.1)
        #expect(!Metrics.schemaValid(brief: brief))
    }

    @Test func attachmentSummaryMetrics_coverSchemaEvidenceAndHallucination() {
        let summary = AIAttachmentSummary(
            summary: "Invoice INV-2026-04 is due April 15.",
            keyFields: [AIKeyField(name: "Amount", value: "$4,250.00")],
            risks: [],
            nextSteps: ["Pay by April 15"],
            evidence: [
                AIAttachmentEvidence(chunkIndex: 0, quote: "Invoice INV-2026-04 for $4,250.00 is due April 15"),
            ],
            confidence: 0.8
        )

        #expect(Metrics.schemaValid(attachmentSummary: summary))
        #expect(Metrics.evidenceCoverage(attachmentSummary: summary) > 0)
        #expect(Metrics.hallucinationRate(
            attachmentSummary: summary,
            sourceText: "Invoice INV-2026-04 for $4,250.00 is due April 15, 2026.",
            chunkCount: 1
        ) == 0)
    }

    // MARK: - Claim Extraction

    @Test func extractClaims_findsDollarAmounts() {
        let brief = AIThreadBrief(
            summary: "Invoice for $4,250.00 and $12,500 pending",
            confidence: 0.9
        )
        let claims = Metrics.extractClaims(from: brief)
        #expect(claims.contains("$4,250.00"))
        #expect(claims.contains("$12,500"))
    }

    @Test func extractClaims_findsDates() {
        let brief = AIThreadBrief(
            summary: "Deadline is April 15, next review May 1",
            confidence: 0.8
        )
        let claims = Metrics.extractClaims(from: brief)
        #expect(claims.contains("April 15"))
        #expect(claims.contains("May 1"))
    }

    @Test func extractClaims_findsEmails() {
        let brief = AIThreadBrief(
            summary: "Request from alice@example.com",
            confidence: 0.7
        )
        let claims = Metrics.extractClaims(from: brief)
        #expect(claims.contains("alice@example.com"))
    }

    // MARK: - Grounding

    @Test func isGrounded_directMatch_returnsTrue() {
        let source = "The project deadline is April 15."
        let input = AIThreadInput(messages: [
            .init(from: "test@test.com", sentAt: .now, bodyText: source),
        ])
        #expect(Metrics.isGrounded("deadline is April 15", in: source, input: input))
    }

    @Test func isGrounded_noMatchingWords_returnsFalse() {
        let source = "Simple greeting message."
        let input = AIThreadInput(messages: [
            .init(from: "test@test.com", sentAt: .now, bodyText: source),
        ])
        #expect(!Metrics.isGrounded("quarterly earnings exceeded expectations", in: source, input: input))
    }
}

// MARK: - EvalCorpus Tests

@Suite("EvalCorpus")
struct EvalCorpusTests {
    @Test func corpusHas20Threads() {
        #expect(EvalCorpus.threads.count == 20)
    }

    @Test func allThreadsHaveUniqueIDs() {
        let ids = EvalCorpus.threads.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func allThreadsHaveAtLeastOneMessage() {
        for (id, input) in EvalCorpus.threads {
            #expect(!input.messages.isEmpty, "Thread \(id) has no messages")
        }
    }
}

// MARK: - EvalRunner Tests

@Suite("EvalRunner")
struct EvalRunnerTests {
    @Test func runWithMockService_producesReport() async throws {
        let corpus: [(id: String, input: AIThreadInput)] = [
            ("test-1", AIThreadInput(messages: [
                .init(from: "a@b.com", sentAt: .now, bodyText: "Hello world"),
            ])),
            ("test-2", AIThreadInput(messages: [
                .init(from: "c@d.com", sentAt: .now, bodyText: "Invoice for $100"),
            ])),
        ]

        let service = MockEvalService()
        let runner = EvalRunner()
        let report = try await runner.run(corpus: corpus, service: service)

        #expect(report.totalThreads == 2)
        #expect(report.successCount == 2)
        #expect(report.task.taskID == "threadBrief")
        #expect(report.schemaValidityRate == 1.0)
        #expect(report.p50Latency >= 0)
        #expect(report.p95Latency >= 0)
    }

    @Test func runWithFailingService_capturesErrors() async throws {
        let corpus: [(id: String, input: AIThreadInput)] = [
            ("fail-1", AIThreadInput(messages: [
                .init(from: "x@y.com", sentAt: .now, bodyText: "Test"),
            ])),
        ]

        let service = FailingEvalService()
        let runner = EvalRunner()
        let report = try await runner.run(corpus: corpus, service: service)

        #expect(report.totalThreads == 1)
        #expect(report.successCount == 0)
        #expect(report.results[0].error != nil)
    }

    @Test func markdownReport_isNotEmpty() async throws {
        let corpus: [(id: String, input: AIThreadInput)] = [
            ("md-1", AIThreadInput(messages: [
                .init(from: "a@b.com", sentAt: .now, bodyText: "Test thread"),
            ])),
        ]

        let service = MockEvalService()
        let runner = EvalRunner()
        let report = try await runner.run(corpus: corpus, service: service)
        let md = report.markdownReport()

        #expect(md.contains("AIEvals"))
        #expect(md.contains("md-1"))
    }
}

// MARK: - Test Helpers

private struct MockEvalService: AIService {
    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        AIThreadBrief(
            summary: "Test summary for \(input.messages.first?.from ?? "unknown")",
            evidence: [],
            confidence: 0.8
        )
    }

    func draftReply(
        _ input: AIThreadInput,
        tone _: AIReplyTone,
        locale _: Locale,
        replyLanguage _: String?
    ) async throws -> AIThreadReply {
        AIThreadReply(body: "Reply for \(input.messages.first?.from ?? "unknown")")
    }
}

private struct FailingEvalService: AIService {
    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        throw AIError.inferenceFailed(NSError(domain: "test", code: 1))
    }

    func draftReply(
        _ input: AIThreadInput,
        tone _: AIReplyTone,
        locale _: Locale,
        replyLanguage _: String?
    ) async throws -> AIThreadReply {
        throw AIError.inferenceFailed(NSError(domain: "test", code: 1))
    }
}
