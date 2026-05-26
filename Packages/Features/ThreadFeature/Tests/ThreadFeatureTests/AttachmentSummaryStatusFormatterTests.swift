import AIKit
import Testing
@testable import ThreadFeature

@Suite("Attachment summary status formatter")
struct AttachmentSummaryStatusFormatterTests {
    @Test func rendersNeutralIdleAndTerminalStates() {
        let attachment = AttachmentInfo(
            id: "att1",
            messageId: "m1",
            accountId: "a1",
            filename: "invoice.pdf",
            sizeBytes: 284_000,
            mime: "application/pdf"
        )
        let cachedSummary = AttachmentSummaryViewData(summary: makeAttachmentSummary(), cached: true)
        let freshSummary = AttachmentSummaryViewData(summary: makeAttachmentSummary(), cached: false)

        #expect(
            AttachmentSummaryStatusFormatter.text(for: attachment, state: .idle)
                == "277 KB \u{00B7} ready to summarize"
        )
        #expect(
            AttachmentSummaryStatusFormatter.text(for: attachment, state: .summarizing)
                == "277 KB \u{00B7} summarizing locally"
        )
        #expect(
            AttachmentSummaryStatusFormatter.text(for: attachment, state: .summary(cachedSummary))
                == "277 KB \u{00B7} cached local summary"
        )
        #expect(
            AttachmentSummaryStatusFormatter.text(for: attachment, state: .summary(freshSummary))
                == "277 KB \u{00B7} summarized locally"
        )
        #expect(
            AttachmentSummaryStatusFormatter.text(for: attachment, state: .unsupported("Unsupported file type."))
                == "277 KB \u{00B7} unsupported"
        )
        #expect(
            AttachmentSummaryStatusFormatter.text(
                for: attachment,
                state: .failed("Could not summarize this attachment.")
            )
                == "277 KB \u{00B7} summary failed"
        )
    }
}

private func makeAttachmentSummary() -> AIAttachmentSummary {
    AIAttachmentSummary(
        summary: "Attachment summary",
        keyFields: [AIKeyField(name: "amount", value: "EUR 1840")],
        risks: [],
        nextSteps: ["Pay invoice"],
        evidence: [AIAttachmentEvidence(chunkIndex: 0, quote: "Amount due: EUR 1840")],
        confidence: 0.9
    )
}
