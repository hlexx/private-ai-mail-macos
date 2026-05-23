import AttachmentKit
import Foundation
import GRDB
import Persistence
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

    @Test func persistenceCacheUpsertsAndFetchesChunks() throws {
        let database = try makeDatabase()
        let scope = AttachmentRAGCacheScope(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: 1
        )
        try seedAttachmentGraph(database, extractionVersion: scope.extractionVersion)
        let cache = PersistenceAttachmentRAGCache(database: database)
        let initialChunks = [
            makeChunk(
                index: 0,
                text: "Invoice total is 42.00",
                attachmentId: scope.attachmentId,
                extractionVersion: "extract-v1",
                policyVersion: "policy-v1",
                evidence: [.page(number: 1)]
            ),
            makeChunk(
                index: 1,
                text: "Payment due Friday",
                attachmentId: scope.attachmentId,
                extractionVersion: "extract-v1",
                policyVersion: "policy-v1",
                evidence: [.byteRange(start: 20, end: 38)]
            ),
        ]

        try cache.upsertChunks(initialChunks, for: scope, createdAt: 200)

        #expect(try cache.fetchChunks(for: scope, policyVersion: "policy-v1") == initialChunks)

        let replacementChunks = [
            makeChunk(
                index: 0,
                text: "Updated invoice total is 84.00",
                attachmentId: scope.attachmentId,
                extractionVersion: "extract-v1",
                policyVersion: "policy-v1",
                evidence: [.page(number: 2)]
            ),
        ]
        try cache.upsertChunks(replacementChunks, for: scope, createdAt: 250)

        #expect(try cache.fetchChunks(for: scope, policyVersion: "policy-v1") == replacementChunks)
        #expect(try chunkRowCount(database, scope: scope) == 1)
    }

    @Test func persistenceArtifactCacheStoresHitsAndMisses() throws {
        let database = try makeDatabase()
        let scope = AttachmentRAGCacheScope(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: 1
        )
        try seedAttachmentGraph(database, extractionVersion: scope.extractionVersion)
        let cache = PersistenceAttachmentRAGCache(database: database)
        let key = AttachmentAIArtifactCacheKey(
            scope: scope,
            chunkingPolicyVersion: "policy-v1",
            modelId: "local-summary",
            promptVersion: "prompt-v1"
        )
        let artifact = AttachmentCachedAIArtifact(
            key: key,
            payloadJSON: "{\"summary\":\"Invoice total is 42.00\"}",
            createdAt: 300,
            updatedAt: 300
        )

        try cache.upsertArtifact(artifact)

        #expect(try cache.fetchArtifact(for: key) == artifact)
        #expect(try cache.fetchArtifact(for: AttachmentAIArtifactCacheKey(
            scope: scope,
            chunkingPolicyVersion: "policy-v1",
            modelId: "other-local-model",
            promptVersion: "prompt-v1"
        )) == nil)
        #expect(try cache.fetchArtifact(for: AttachmentAIArtifactCacheKey(
            scope: scope,
            chunkingPolicyVersion: "policy-v1",
            modelId: "local-summary",
            promptVersion: "prompt-v2"
        )) == nil)
    }

    @Test func persistenceCacheInvalidatesWhenExtractionOrPolicyVersionChanges() throws {
        let database = try makeDatabase()
        let scopeV1 = AttachmentRAGCacheScope(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: 1
        )
        let scopeV2 = AttachmentRAGCacheScope(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: 2
        )
        try seedAttachmentGraph(database, extractionVersion: scopeV1.extractionVersion)
        try seedExtraction(database, scope: scopeV2)
        let cache = PersistenceAttachmentRAGCache(database: database)
        let policyV1Chunk = makeChunk(
            index: 0,
            text: "Policy one chunk",
            attachmentId: scopeV1.attachmentId,
            extractionVersion: "extract-v1",
            policyVersion: "policy-v1"
        )
        let policyV2Chunk = makeChunk(
            index: 0,
            text: "Policy two chunk",
            attachmentId: scopeV1.attachmentId,
            extractionVersion: "extract-v1",
            policyVersion: "policy-v2"
        )

        try cache.upsertChunks([policyV1Chunk], for: scopeV1, createdAt: 400)

        #expect(try cache.fetchChunks(for: scopeV1, policyVersion: "policy-v1") == [policyV1Chunk])
        #expect(try cache.fetchChunks(for: scopeV1, policyVersion: "policy-v2") == nil)
        #expect(try cache.fetchChunks(for: scopeV2, policyVersion: "policy-v1") == nil)

        try cache.upsertChunks([policyV2Chunk], for: scopeV1, createdAt: 450)

        #expect(try cache.fetchChunks(for: scopeV1, policyVersion: "policy-v1") == nil)
        #expect(try cache.fetchChunks(for: scopeV1, policyVersion: "policy-v2") == [policyV2Chunk])

        let artifactKey = AttachmentAIArtifactCacheKey(
            scope: scopeV1,
            chunkingPolicyVersion: "policy-v2",
            modelId: "local-summary",
            promptVersion: "prompt-v1"
        )
        try cache.upsertArtifact(AttachmentCachedAIArtifact(
            key: artifactKey,
            payloadJSON: "{\"summary\":\"Policy two\"}",
            createdAt: 500,
            updatedAt: 500
        ))

        #expect(try cache.fetchArtifact(for: artifactKey) != nil)
        #expect(try cache.fetchArtifact(for: AttachmentAIArtifactCacheKey(
            scope: scopeV1,
            chunkingPolicyVersion: "policy-v1",
            modelId: "local-summary",
            promptVersion: "prompt-v1"
        )) == nil)
        #expect(try cache.fetchArtifact(for: AttachmentAIArtifactCacheKey(
            scope: scopeV2,
            chunkingPolicyVersion: "policy-v2",
            modelId: "local-summary",
            promptVersion: "prompt-v1"
        )) == nil)
    }

    @Test func persistenceCacheRowsCascadeWithExtractionForeignKey() throws {
        let database = try makeDatabase()
        let scope = AttachmentRAGCacheScope(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: 1
        )
        try seedAttachmentGraph(database, extractionVersion: scope.extractionVersion)
        let cache = PersistenceAttachmentRAGCache(database: database)
        try cache.upsertChunks([
            makeChunk(
                index: 0,
                text: "Chunk to cascade",
                attachmentId: scope.attachmentId,
                extractionVersion: "extract-v1",
                policyVersion: "policy-v1"
            ),
        ], for: scope, createdAt: 600)
        try cache.upsertArtifact(AttachmentCachedAIArtifact(
            key: AttachmentAIArtifactCacheKey(
                scope: scope,
                chunkingPolicyVersion: "policy-v1",
                modelId: "local-summary",
                promptVersion: "prompt-v1"
            ),
            payloadJSON: "{\"summary\":\"Cascade\"}",
            createdAt: 610,
            updatedAt: 610
        ))

        _ = try database.dbQueue.write { db in
            try AttachmentExtractionRecord
                .filter(Column("account_id") == scope.accountId)
                .filter(Column("message_id") == scope.messageId)
                .filter(Column("attachment_id") == scope.attachmentId)
                .filter(Column("extraction_version") == scope.extractionVersion)
                .deleteAll(db)
        }

        #expect(try chunkRowCount(database, scope: scope) == 0)
        #expect(try artifactRowCount(database, scope: scope) == 0)
    }

    @Test func artifactCacheKeyIsDeterministicAndVersioned() {
        let scope = AttachmentRAGCacheScope(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: 1
        )
        let key = AttachmentAIArtifactCacheKey(
            scope: scope,
            chunkingPolicyVersion: "policy-v1",
            modelId: "local-summary",
            promptVersion: "prompt-v1"
        )
        let sameKey = AttachmentAIArtifactCacheKey(
            scope: scope,
            chunkingPolicyVersion: "policy-v1",
            modelId: "local-summary",
            promptVersion: "prompt-v1"
        )
        let changedPolicy = AttachmentAIArtifactCacheKey(
            scope: scope,
            chunkingPolicyVersion: "policy-v2",
            modelId: "local-summary",
            promptVersion: "prompt-v1"
        )

        #expect(key.cacheKey == sameKey.cacheKey)
        #expect(key.cacheKey.hasPrefix("attachment-ai-artifact:v1:"))
        #expect(key.cacheKey != changedPolicy.cacheKey)
    }

    @Test func summaryOrchestrationPersistsAndReusesCachedArtifact() async throws {
        let database = try makeDatabase()
        let scope = testScope()
        try seedAttachmentGraph(database, extractionVersion: scope.extractionVersion)
        let cache = PersistenceAttachmentRAGCache(database: database)
        let summarizer = CountingAttachmentSummarizer()
        let chunker = LocalAttachmentChunker(policy: testPolicy(maxCharacters: 200))
        let request = AttachmentSummaryRequest(
            scope: scope,
            extractionVersion: "extract-v1",
            extractionResult: AttachmentExtractionResult(
                status: .complete,
                extractedText: [
                    AttachmentExtractedText(
                        text: "Invoice: INV-42\nTotal: 42.00\nPayment due Friday",
                        locator: .page(number: 1)
                    ),
                    AttachmentExtractedText(
                        text: "Urgent approval required before the deadline.",
                        locator: .page(number: 2)
                    ),
                ]
            ),
            query: AttachmentRetrievalQuery(text: "invoice total due urgent approval", limit: 5),
            createdAt: 700
        )
        let orchestrator = AttachmentSummaryOrchestrator(
            cache: cache,
            chunker: chunker,
            summarizer: summarizer
        )

        let first = await orchestrator.summarize(request)

        guard case let .complete(firstOutput, firstSource) = first else {
            Issue.record("Expected generated complete summary, got \(first)")
            return
        }
        #expect(firstSource == .generated)
        #expect(firstOutput.summary == "summary from 2 chunks")
        #expect(firstOutput.keyFields.first?.label == "chunks")
        #expect(firstOutput.modelId == summarizer.modelId)
        #expect(firstOutput.promptVersion == summarizer.promptVersion)
        #expect(summarizer.callCount == 1)
        #expect(try artifactRowCount(database, scope: scope) == 1)

        let second = await orchestrator.summarize(request)

        guard case let .complete(secondOutput, secondSource) = second else {
            Issue.record("Expected cached complete summary, got \(second)")
            return
        }
        #expect(secondSource == .cached)
        #expect(secondOutput == firstOutput)
        #expect(summarizer.callCount == 1)
    }

    @Test func summaryOrchestrationReturnsIncompleteUnsupportedAndFailedStatuses() async {
        let scope = testScope()
        let chunker = LocalAttachmentChunker(policy: testPolicy(maxCharacters: 200))
        let orchestrator = AttachmentSummaryOrchestrator(
            cache: InMemoryAttachmentRAGCache(),
            chunker: chunker,
            summarizer: DeterministicAttachmentSummarizer()
        )

        let incomplete = await orchestrator.summarize(AttachmentSummaryRequest(
            scope: scope,
            extractionVersion: "extract-v1",
            extractionResult: AttachmentExtractionResult(
                status: .incomplete,
                extractedText: [
                    AttachmentExtractedText(
                        text: "Invoice total is 42.00. Payment due Friday.",
                        locator: .page(number: 1)
                    ),
                ]
            ),
            query: AttachmentRetrievalQuery(text: "invoice total due", limit: 3),
            createdAt: 800
        ))

        guard case let .incomplete(incompleteOutput, incompleteReason, incompleteSource) = incomplete else {
            Issue.record("Expected incomplete summary, got \(incomplete)")
            return
        }
        #expect(incompleteOutput?.summary == "Invoice total is 42.00. Payment due Friday.")
        #expect(incompleteOutput?.confidence == 0.56)
        #expect(incompleteReason == .extractionIncomplete)
        #expect(incompleteSource == .generated)

        let unsupported = await orchestrator.summarize(AttachmentSummaryRequest(
            scope: scope,
            extractionVersion: "extract-v1",
            extractionResult: AttachmentExtractionResult(status: .unsupported),
            query: AttachmentRetrievalQuery(text: "invoice", limit: 3),
            createdAt: 810
        ))
        #expect(unsupported == .unsupported(.unsupportedExtraction))

        let failed = await orchestrator.summarize(AttachmentSummaryRequest(
            scope: scope,
            extractionVersion: "extract-v1",
            extractionResult: AttachmentExtractionResult(status: .failed),
            query: AttachmentRetrievalQuery(text: "invoice", limit: 3),
            createdAt: 820
        ))

        guard case let .failed(failure) = failed else {
            Issue.record("Expected failed summary, got \(failed)")
            return
        }
        #expect(failure.code == .extractionFailed)
    }

    @Test func summaryOrchestrationReportsNoRelevantChunksAsIncomplete() async {
        let orchestrator = AttachmentSummaryOrchestrator(
            cache: InMemoryAttachmentRAGCache(),
            chunker: LocalAttachmentChunker(policy: testPolicy(maxCharacters: 200)),
            summarizer: DeterministicAttachmentSummarizer()
        )

        let result = await orchestrator.summarize(AttachmentSummaryRequest(
            scope: testScope(),
            extractionVersion: "extract-v1",
            extractionResult: AttachmentExtractionResult(
                status: .complete,
                extractedText: [
                    AttachmentExtractedText(
                        text: "Quarterly roadmap notes and meeting agenda.",
                        locator: .section(name: "body")
                    ),
                ]
            ),
            query: AttachmentRetrievalQuery(text: "invoice", limit: 3),
            createdAt: 830
        ))

        #expect(result == .incomplete(nil, reason: .noRelevantChunks, source: nil))
    }

    @Test func summaryOrchestrationMakesNoNetworkRequestsByDefault() async {
        _ = URLProtocol.registerClass(SummarySpyURLProtocol.self)
        defer { URLProtocol.unregisterClass(SummarySpyURLProtocol.self) }
        SummarySpyURLProtocol.reset()

        let result = await AttachmentSummaryOrchestrator(
            cache: InMemoryAttachmentRAGCache(),
            chunker: LocalAttachmentChunker(policy: testPolicy(maxCharacters: 200)),
            summarizer: DeterministicAttachmentSummarizer()
        )
        .summarize(AttachmentSummaryRequest(
            scope: testScope(),
            extractionVersion: "extract-v1",
            extractionResult: AttachmentExtractionResult(
                status: .complete,
                extractedText: [
                    AttachmentExtractedText(
                        text: "Invoice: INV-42\nTotal: 42.00\nPayment due Friday",
                        locator: .page(number: 1)
                    ),
                ]
            ),
            query: AttachmentRetrievalQuery(text: "invoice total due", limit: 3),
            createdAt: 840
        ))

        guard case .complete = result else {
            Issue.record("Expected complete summary, got \(result)")
            return
        }
        #expect(SummarySpyURLProtocol.requestCount == 0)
    }

    @Test func summaryOrchestrationFailsClosedWithoutConfiguredFallback() async {
        _ = URLProtocol.registerClass(SummarySpyURLProtocol.self)
        defer { URLProtocol.unregisterClass(SummarySpyURLProtocol.self) }
        SummarySpyURLProtocol.reset()

        let result = await AttachmentSummaryOrchestrator(
            cache: InMemoryAttachmentRAGCache(),
            chunker: LocalAttachmentChunker(policy: testPolicy(maxCharacters: 200)),
            summarizer: nil
        )
        .summarize(AttachmentSummaryRequest(
            scope: testScope(),
            extractionVersion: "extract-v1",
            extractionResult: AttachmentExtractionResult(
                status: .complete,
                extractedText: [
                    AttachmentExtractedText(
                        text: "Invoice total is 42.00. Payment due Friday.",
                        locator: .page(number: 1)
                    ),
                ]
            ),
            query: AttachmentRetrievalQuery(text: "invoice total due", limit: 3),
            createdAt: 850
        ))

        guard case let .failed(failure) = result else {
            Issue.record("Expected closed failure, got \(result)")
            return
        }
        #expect(failure.code == .cloudFallbackNotConfigured)
        #expect(SummarySpyURLProtocol.requestCount == 0)
    }

    private func testPolicy(maxCharacters: Int) -> AttachmentChunkingPolicy {
        AttachmentChunkingPolicy(
            version: "test-policy-v1",
            maxCharacters: maxCharacters,
            overlapCharacters: 0
        )
    }

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase.openInMemorySync()
    }

    private func seedAttachmentGraph(
        _ database: AppDatabase,
        extractionVersion: Int
    ) throws {
        try database.dbQueue.write { db in
            try AccountRecord(id: "a1", email: "test@gmail.com", createdAt: 1).insert(db)
            try ThreadRecord(id: "t1", accountId: "a1", lastMessageAt: 2, messageCount: 1).insert(db)
            try MessageRecord(id: "m1", threadId: "t1", accountId: "a1", sentAt: 2).insert(db)
            try AttachmentRecord(
                id: "att1",
                messageId: "m1",
                accountId: "a1",
                filename: "invoice.pdf",
                mime: "application/pdf",
                sizeBytes: 4096
            ).insert(db)
            try AttachmentExtractionRecord(
                accountId: "a1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: extractionVersion,
                status: "succeeded",
                contentHash: "sha256:extract-\(extractionVersion)",
                createdAt: 100,
                updatedAt: 100,
                completedAt: 100
            ).insert(db)
        }
    }

    private func seedExtraction(
        _ database: AppDatabase,
        scope: AttachmentRAGCacheScope
    ) throws {
        try database.dbQueue.write { db in
            try AttachmentExtractionRecord(
                accountId: scope.accountId,
                messageId: scope.messageId,
                attachmentId: scope.attachmentId,
                extractionVersion: scope.extractionVersion,
                status: "succeeded",
                contentHash: "sha256:extract-\(scope.extractionVersion)",
                createdAt: 100,
                updatedAt: 100,
                completedAt: 100
            ).insert(db)
        }
    }

    private func chunkRowCount(_ database: AppDatabase, scope: AttachmentRAGCacheScope) throws -> Int {
        try database.dbQueue.read { db in
            try AttachmentChunkRecord
                .filter(Column("account_id") == scope.accountId)
                .filter(Column("message_id") == scope.messageId)
                .filter(Column("attachment_id") == scope.attachmentId)
                .filter(Column("extraction_version") == scope.extractionVersion)
                .fetchCount(db)
        }
    }

    private func artifactRowCount(_ database: AppDatabase, scope: AttachmentRAGCacheScope) throws -> Int {
        try database.dbQueue.read { db in
            try AttachmentAIArtifactRecord
                .filter(Column("account_id") == scope.accountId)
                .filter(Column("message_id") == scope.messageId)
                .filter(Column("attachment_id") == scope.attachmentId)
                .filter(Column("extraction_version") == scope.extractionVersion)
                .fetchCount(db)
        }
    }

    private func testScope(extractionVersion: Int = 1) -> AttachmentRAGCacheScope {
        AttachmentRAGCacheScope(
            accountId: "a1",
            messageId: "m1",
            attachmentId: "att1",
            extractionVersion: extractionVersion
        )
    }

    private func makeChunk(
        index: Int,
        text: String,
        attachmentId: String = "att",
        extractionVersion: String = "extract-v1",
        policyVersion: String = "policy-v1",
        evidence: [AttachmentEvidenceSource] = [.section(name: "body")]
    ) -> AttachmentChunk {
        AttachmentChunk(
            id: "chunk-\(index)",
            attachmentId: attachmentId,
            extractionVersion: extractionVersion,
            policyVersion: policyVersion,
            index: index,
            sourceIndex: index,
            text: text,
            evidence: evidence
        )
    }
}

private final class CountingAttachmentSummarizer: AttachmentSummarizer, @unchecked Sendable {
    let modelId = "local-counting-summary"
    let promptVersion = "prompt-counting-v1"
    private(set) var callCount = 0

    func summarize(_ input: AttachmentSummaryInput) async throws -> AttachmentSummaryOutput {
        callCount += 1
        let evidenceChunkIds = input.chunks.map(\.id)
        return AttachmentSummaryOutput(
            summary: "summary from \(input.chunks.count) chunks",
            keyFields: [
                AttachmentSummaryKeyField(
                    label: "chunks",
                    value: "\(input.chunks.count)",
                    evidenceChunkIds: evidenceChunkIds
                ),
            ],
            risks: [],
            nextSteps: [
                AttachmentSummaryFinding(
                    text: "Review the attachment evidence.",
                    evidenceChunkIds: evidenceChunkIds
                ),
            ],
            evidenceChunkIds: evidenceChunkIds,
            modelId: modelId,
            promptVersion: promptVersion,
            confidence: 0.9
        )
    }
}

private final class InMemoryAttachmentRAGCache: AttachmentRAGCache, @unchecked Sendable {
    private var chunksByKey: [String: [AttachmentChunk]] = [:]
    private var artifactsByKey: [String: AttachmentCachedAIArtifact] = [:]

    func upsertChunks(
        _ chunks: [AttachmentChunk],
        for scope: AttachmentRAGCacheScope,
        createdAt: Int
    ) throws {
        guard let policyVersion = chunks.first?.policyVersion else {
            return
        }

        for chunk in chunks {
            guard chunk.attachmentId == scope.attachmentId else {
                throw AttachmentRAGCacheError.chunkAttachmentMismatch(
                    chunkId: chunk.id,
                    expectedAttachmentId: scope.attachmentId,
                    actualAttachmentId: chunk.attachmentId
                )
            }
            guard chunk.policyVersion == policyVersion else {
                throw AttachmentRAGCacheError.chunkPolicyMismatch(
                    chunkId: chunk.id,
                    expectedPolicyVersion: policyVersion,
                    actualPolicyVersion: chunk.policyVersion
                )
            }
        }

        chunksByKey[chunkCacheKey(scope: scope, policyVersion: policyVersion)] = chunks
    }

    func fetchChunks(
        for scope: AttachmentRAGCacheScope,
        policyVersion: String
    ) throws -> [AttachmentChunk]? {
        chunksByKey[chunkCacheKey(scope: scope, policyVersion: policyVersion)]
    }

    func upsertArtifact(_ artifact: AttachmentCachedAIArtifact) throws {
        artifactsByKey[artifact.key.cacheKey] = artifact
    }

    func fetchArtifact(for key: AttachmentAIArtifactCacheKey) throws -> AttachmentCachedAIArtifact? {
        artifactsByKey[key.cacheKey]
    }

    private func chunkCacheKey(scope: AttachmentRAGCacheScope, policyVersion: String) -> String {
        [
            scope.accountId,
            scope.messageId,
            scope.attachmentId,
            String(scope.extractionVersion),
            policyVersion,
        ].joined(separator: "|")
    }
}

private final class SummarySpyURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestCount = 0

    static func reset() {
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        let error = NSError(
            domain: "AttachmentSummaryNetworkIsolation",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected network request during attachment summary orchestration"]
        )
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}
