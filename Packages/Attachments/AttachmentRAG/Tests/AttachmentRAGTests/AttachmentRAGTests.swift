import AttachmentKit
import Testing
@testable import AttachmentRAG

@Suite("AttachmentRAG")
struct AttachmentRAGTests {
    @Test func moduleNameIsExported() {
        #expect(AttachmentRAG.moduleName == "AttachmentRAG")
    }

    @Test func chunkerPreservesPDFPageEvidence() {
        let result = AttachmentExtractionResult(
            status: .complete,
            extractedText: [
                AttachmentExtractedText(text: "Invoice 100\nTotal 42", locator: .page(number: 1)),
                AttachmentExtractedText(text: "Payment due Friday", locator: .page(number: 2)),
            ]
        )

        let chunks = LocalAttachmentChunker(policy: testPolicy(maxCharacters: 100))
            .chunks(for: AttachmentChunkingInput(
                attachmentId: "att-pdf",
                extractionVersion: "extract-v1",
                extractionResult: result
            ))

        #expect(chunks.count == 2)
        #expect(chunks[0].index == 0)
        #expect(chunks[0].sourceIndex == 0)
        #expect(chunks[0].evidence == [.page(number: 1)])
        #expect(chunks[1].index == 1)
        #expect(chunks[1].sourceIndex == 1)
        #expect(chunks[1].evidence == [.page(number: 2)])
        #expect(chunks[0].id != chunks[1].id)
    }

    @Test func chunkerPreservesTextByteRangeEvidenceWhenSplitting() {
        let result = AttachmentExtractionResult(
            status: .complete,
            extractedText: [
                AttachmentExtractedText(
                    text: "  Alpha beta gamma delta epsilon  ",
                    locator: .byteRange(start: 10, end: 44)
                ),
            ]
        )

        let chunks = LocalAttachmentChunker(policy: testPolicy(maxCharacters: 16))
            .chunks(for: AttachmentChunkingInput(
                attachmentId: "att-text",
                extractionVersion: "extract-v1",
                extractionResult: result
            ))

        #expect(chunks.map(\.text) == ["Alpha beta", "gamma delta", "epsilon"])
        #expect(chunks.map(\.evidence) == [
            [.byteRange(start: 12, end: 22)],
            [.byteRange(start: 23, end: 34)],
            [.byteRange(start: 35, end: 42)],
        ])
    }

    @Test func chunkerDropsEmptyAndUnsupportedExtractionResults() {
        let incomplete = AttachmentExtractionResult(
            status: .incomplete,
            extractedText: [
                AttachmentExtractedText(text: " \n\t", locator: .section(name: "blank")),
                AttachmentExtractedText(text: "Usable section", locator: .section(name: "body")),
            ]
        )
        let unsupported = AttachmentExtractionResult(status: .unsupported)
        let chunker = LocalAttachmentChunker(policy: testPolicy(maxCharacters: 100))

        let incompleteChunks = chunker.chunks(for: AttachmentChunkingInput(
            attachmentId: "att-incomplete",
            extractionVersion: "extract-v1",
            extractionResult: incomplete
        ))
        let unsupportedChunks = chunker.chunks(for: AttachmentChunkingInput(
            attachmentId: "att-unsupported",
            extractionVersion: "extract-v1",
            extractionResult: unsupported
        ))

        #expect(incompleteChunks.map(\.text) == ["Usable section"])
        #expect(incompleteChunks.first?.evidence == [.section(name: "body")])
        #expect(unsupportedChunks.isEmpty)
    }

    @Test func chunkerProducesStableSourceOrderAndStableChunkIds() {
        let result = AttachmentExtractionResult(
            status: .complete,
            extractedText: [
                AttachmentExtractedText(
                    text: "First section has enough words to split cleanly",
                    locator: .section(name: "first")
                ),
                AttachmentExtractedText(text: "Second section stays last", locator: .section(name: "second")),
            ]
        )
        let chunker = LocalAttachmentChunker(policy: testPolicy(maxCharacters: 24))
        let input = AttachmentChunkingInput(
            attachmentId: "att-order",
            extractionVersion: "extract-v1",
            extractionResult: result
        )

        let firstRun = chunker.chunks(for: input)
        let secondRun = chunker.chunks(for: input)

        #expect(firstRun.map(\.text) == [
            "First section has",
            "enough words to split",
            "cleanly",
            "Second section stays",
            "last",
        ])
        #expect(firstRun.map(\.sourceIndex) == [0, 0, 0, 1, 1])
        #expect(firstRun.map(\.id) == secondRun.map(\.id))
    }

    @Test func retrieverRanksChunksByDeterministicLexicalScore() {
        let chunks = [
            makeChunk(index: 0, text: "Quarterly roadmap and team notes"),
            makeChunk(index: 1, text: "Invoice total total due Friday"),
            makeChunk(index: 2, text: "Invoice due date moved to Monday"),
        ]

        let results = LocalAttachmentRetriever()
            .retrieve(AttachmentRetrievalQuery(text: "invoice total due", limit: 3), from: chunks)

        #expect(results.map(\.chunk.index) == [1, 2])
        #expect(results[0].matchedTerms == ["invoice", "total", "due"])
        #expect(results[0].score > results[1].score)
    }

    @Test func chunkCacheKeyIsDeterministicAndVersioned() {
        let input = AttachmentChunkCacheKeyInput(
            attachmentId: "att-1",
            extractionVersion: "extract-v1",
            extractionContentHash: "sha256:abc",
            chunkingPolicyVersion: "policy-v1"
        )
        let sameInput = AttachmentChunkCacheKeyInput(
            attachmentId: "att-1",
            extractionVersion: "extract-v1",
            extractionContentHash: "sha256:abc",
            chunkingPolicyVersion: "policy-v1"
        )
        let changedPolicy = AttachmentChunkCacheKeyInput(
            attachmentId: "att-1",
            extractionVersion: "extract-v1",
            extractionContentHash: "sha256:abc",
            chunkingPolicyVersion: "policy-v2"
        )

        #expect(input.cacheKey == sameInput.cacheKey)
        #expect(input.cacheKey.hasPrefix("attachment-chunks:v1:"))
        #expect(input.cacheKey != changedPolicy.cacheKey)
    }

    private func testPolicy(maxCharacters: Int) -> AttachmentChunkingPolicy {
        AttachmentChunkingPolicy(
            version: "test-policy-v1",
            maxCharacters: maxCharacters,
            overlapCharacters: 0
        )
    }

    private func makeChunk(index: Int, text: String) -> AttachmentChunk {
        AttachmentChunk(
            id: "chunk-\(index)",
            attachmentId: "att",
            extractionVersion: "extract-v1",
            policyVersion: "policy-v1",
            index: index,
            sourceIndex: index,
            text: text,
            evidence: [.section(name: "body")]
        )
    }
}
