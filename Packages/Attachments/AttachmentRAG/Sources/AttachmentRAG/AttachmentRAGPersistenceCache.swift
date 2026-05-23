import Foundation
import GRDB
import Persistence

public struct AttachmentRAGCacheScope: Equatable, Sendable {
    public var accountId: String
    public var messageId: String
    public var attachmentId: String
    public var extractionVersion: Int

    public init(
        accountId: String,
        messageId: String,
        attachmentId: String,
        extractionVersion: Int
    ) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
        self.extractionVersion = extractionVersion
    }
}

public struct AttachmentAIArtifactCacheKey: Equatable, Sendable {
    public static let summaryKind = "summary"

    public var scope: AttachmentRAGCacheScope
    public var artifactKind: String
    public var chunkingPolicyVersion: String
    public var modelId: String
    public var promptVersion: String

    public init(
        scope: AttachmentRAGCacheScope,
        artifactKind: String = Self.summaryKind,
        chunkingPolicyVersion: String,
        modelId: String,
        promptVersion: String
    ) {
        precondition(!artifactKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        precondition(!chunkingPolicyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        precondition(!modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        precondition(!promptVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.scope = scope
        self.artifactKind = artifactKind
        self.chunkingPolicyVersion = chunkingPolicyVersion
        self.modelId = modelId
        self.promptVersion = promptVersion
    }

    public var cacheKey: String {
        let digest = attachmentRAGStableDigest(attachmentRAGLengthPrefixedFields([
            scope.accountId,
            scope.messageId,
            scope.attachmentId,
            String(scope.extractionVersion),
            artifactKind,
            chunkingPolicyVersion,
            modelId,
            promptVersion,
        ]))
        return "attachment-ai-artifact:v1:\(digest)"
    }

    var storageArtifactVersion: Int {
        stablePositiveStorageVersion(cacheKey)
    }
}

public struct AttachmentCachedAIArtifact: Equatable, Sendable {
    public var key: AttachmentAIArtifactCacheKey
    public var payloadJSON: String
    public var createdAt: Int
    public var updatedAt: Int

    public init(
        key: AttachmentAIArtifactCacheKey,
        payloadJSON: String,
        createdAt: Int,
        updatedAt: Int
    ) {
        self.key = key
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public protocol AttachmentRAGCache: Sendable {
    func upsertChunks(
        _ chunks: [AttachmentChunk],
        for scope: AttachmentRAGCacheScope,
        createdAt: Int
    ) throws

    func fetchChunks(
        for scope: AttachmentRAGCacheScope,
        policyVersion: String
    ) throws -> [AttachmentChunk]?

    func upsertArtifact(_ artifact: AttachmentCachedAIArtifact) throws

    func fetchArtifact(for key: AttachmentAIArtifactCacheKey) throws -> AttachmentCachedAIArtifact?
}

public enum AttachmentRAGCacheError: Error, Equatable, Sendable {
    case chunkAttachmentMismatch(chunkId: String, expectedAttachmentId: String, actualAttachmentId: String)
    case chunkPolicyMismatch(chunkId: String, expectedPolicyVersion: String, actualPolicyVersion: String)
    case unreadableChunkMetadata(attachmentId: String, chunkIndex: Int)
    case unsupportedEvidenceMetadata(String)
}

public struct PersistenceAttachmentRAGCache: AttachmentRAGCache {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func upsertChunks(
        _ chunks: [AttachmentChunk],
        for scope: AttachmentRAGCacheScope,
        createdAt: Int
    ) throws {
        for chunk in chunks {
            guard chunk.attachmentId == scope.attachmentId else {
                throw AttachmentRAGCacheError.chunkAttachmentMismatch(
                    chunkId: chunk.id,
                    expectedAttachmentId: scope.attachmentId,
                    actualAttachmentId: chunk.attachmentId
                )
            }
        }

        let records = try chunks.sorted { lhs, rhs in
            if lhs.index != rhs.index {
                return lhs.index < rhs.index
            }
            return lhs.id < rhs.id
        }
        .map { chunk in
            try Self.record(for: chunk, scope: scope, createdAt: createdAt)
        }

        try database.dbQueue.write { db in
            try Self.deleteChunkRows(scope: scope, db: db)
            for record in records {
                try record.insert(db)
            }
        }
    }

    public func fetchChunks(
        for scope: AttachmentRAGCacheScope,
        policyVersion: String
    ) throws -> [AttachmentChunk]? {
        let records = try database.dbQueue.read { db in
            try AttachmentChunkRecord
                .filter(Column("account_id") == scope.accountId)
                .filter(Column("message_id") == scope.messageId)
                .filter(Column("attachment_id") == scope.attachmentId)
                .filter(Column("extraction_version") == scope.extractionVersion)
                .order(Column("chunk_index").asc)
                .fetchAll(db)
        }

        guard !records.isEmpty else { return nil }

        var chunks: [AttachmentChunk] = []
        for record in records {
            let metadata = try Self.metadata(from: record)
            guard metadata.policyVersion == policyVersion else {
                return nil
            }
            chunks.append(try Self.chunk(from: record, metadata: metadata))
        }
        return chunks
    }

    public func upsertArtifact(_ artifact: AttachmentCachedAIArtifact) throws {
        let key = artifact.key
        let scope = key.scope
        let record = AttachmentAIArtifactRecord(
            accountId: scope.accountId,
            messageId: scope.messageId,
            attachmentId: scope.attachmentId,
            extractionVersion: scope.extractionVersion,
            artifactKind: key.artifactKind,
            artifactVersion: key.storageArtifactVersion,
            modelId: key.modelId,
            contentHash: key.cacheKey,
            payloadJson: artifact.payloadJSON,
            createdAt: artifact.createdAt,
            updatedAt: artifact.updatedAt
        )

        try database.dbQueue.write { db in
            try record.save(db)
        }
    }

    public func fetchArtifact(for key: AttachmentAIArtifactCacheKey) throws -> AttachmentCachedAIArtifact? {
        let scope = key.scope
        let record = try database.dbQueue.read { db in
            try AttachmentAIArtifactRecord
                .filter(Column("account_id") == scope.accountId)
                .filter(Column("message_id") == scope.messageId)
                .filter(Column("attachment_id") == scope.attachmentId)
                .filter(Column("extraction_version") == scope.extractionVersion)
                .filter(Column("artifact_kind") == key.artifactKind)
                .filter(Column("artifact_version") == key.storageArtifactVersion)
                .fetchOne(db)
        }

        guard let record,
              record.modelId == key.modelId,
              record.contentHash == key.cacheKey else {
            return nil
        }

        return AttachmentCachedAIArtifact(
            key: key,
            payloadJSON: record.payloadJson,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private static func record(
        for chunk: AttachmentChunk,
        scope: AttachmentRAGCacheScope,
        createdAt: Int
    ) throws -> AttachmentChunkRecord {
        let metadata = StoredAttachmentChunkReference(
            chunkId: chunk.id,
            chunkExtractionVersion: chunk.extractionVersion,
            policyVersion: chunk.policyVersion,
            sourceIndex: chunk.sourceIndex,
            evidence: chunk.evidence.map(StoredEvidenceSource.init)
        )
        let primaryEvidence = chunk.evidence.first

        return AttachmentChunkRecord(
            accountId: scope.accountId,
            messageId: scope.messageId,
            attachmentId: scope.attachmentId,
            extractionVersion: scope.extractionVersion,
            chunkIndex: chunk.index,
            contentText: chunk.text,
            sourceReference: try metadata.storageValue(),
            pageNumber: primaryEvidence?.pageNumber,
            sourceStart: primaryEvidence?.sourceStart,
            sourceEnd: primaryEvidence?.sourceEnd,
            tokenCount: approximateTokenCount(in: chunk.text),
            createdAt: createdAt
        )
    }

    private static func chunk(
        from record: AttachmentChunkRecord,
        metadata: StoredAttachmentChunkReference
    ) throws -> AttachmentChunk {
        AttachmentChunk(
            id: metadata.chunkId,
            attachmentId: record.attachmentId,
            extractionVersion: metadata.chunkExtractionVersion,
            policyVersion: metadata.policyVersion,
            index: record.chunkIndex,
            sourceIndex: metadata.sourceIndex,
            text: record.contentText,
            evidence: try metadata.evidence.map { try $0.domainValue }
        )
    }

    private static func metadata(
        from record: AttachmentChunkRecord
    ) throws -> StoredAttachmentChunkReference {
        guard let sourceReference = record.sourceReference,
              let data = sourceReference.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(StoredAttachmentChunkReference.self, from: data),
              metadata.schemaVersion == StoredAttachmentChunkReference.currentSchemaVersion else {
            throw AttachmentRAGCacheError.unreadableChunkMetadata(
                attachmentId: record.attachmentId,
                chunkIndex: record.chunkIndex
            )
        }
        return metadata
    }

    private static func deleteChunkRows(scope: AttachmentRAGCacheScope, db: Database) throws {
        try AttachmentChunkRecord
            .filter(Column("account_id") == scope.accountId)
            .filter(Column("message_id") == scope.messageId)
            .filter(Column("attachment_id") == scope.attachmentId)
            .filter(Column("extraction_version") == scope.extractionVersion)
            .deleteAll(db)
    }
}

private struct StoredAttachmentChunkReference: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var chunkId: String
    var chunkExtractionVersion: String
    var policyVersion: String
    var sourceIndex: Int
    var evidence: [StoredEvidenceSource]

    init(
        chunkId: String,
        chunkExtractionVersion: String,
        policyVersion: String,
        sourceIndex: Int,
        evidence: [StoredEvidenceSource]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.chunkId = chunkId
        self.chunkExtractionVersion = chunkExtractionVersion
        self.policyVersion = policyVersion
        self.sourceIndex = sourceIndex
        self.evidence = evidence
    }

    func storageValue() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

private struct StoredEvidenceSource: Codable, Equatable, Sendable {
    var kind: String
    var pageNumber: Int?
    var start: Int?
    var end: Int?
    var sectionName: String?
    var x: Double?
    var y: Double?
    var width: Double?
    var height: Double?
    var confidence: Float?

    init(_ evidence: AttachmentEvidenceSource) {
        switch evidence {
        case let .page(number):
            self.kind = "page"
            self.pageNumber = number
        case let .byteRange(start, end):
            self.kind = "byteRange"
            self.start = start
            self.end = end
        case let .section(name):
            self.kind = "section"
            self.sectionName = name
        case let .imageRegion(x, y, width, height, confidence):
            self.kind = "imageRegion"
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.confidence = confidence
        }
    }

    var domainValue: AttachmentEvidenceSource {
        get throws {
            switch kind {
            case "page":
                guard let pageNumber else {
                    throw AttachmentRAGCacheError.unsupportedEvidenceMetadata(kind)
                }
                return .page(number: pageNumber)
            case "byteRange":
                guard let start, let end else {
                    throw AttachmentRAGCacheError.unsupportedEvidenceMetadata(kind)
                }
                return .byteRange(start: start, end: end)
            case "section":
                guard let sectionName else {
                    throw AttachmentRAGCacheError.unsupportedEvidenceMetadata(kind)
                }
                return .section(name: sectionName)
            case "imageRegion":
                guard let x, let y, let width, let height, let confidence else {
                    throw AttachmentRAGCacheError.unsupportedEvidenceMetadata(kind)
                }
                return .imageRegion(x: x, y: y, width: width, height: height, confidence: confidence)
            default:
                throw AttachmentRAGCacheError.unsupportedEvidenceMetadata(kind)
            }
        }
    }
}

private extension AttachmentEvidenceSource {
    var pageNumber: Int? {
        guard case let .page(number) = self else { return nil }
        return number
    }

    var sourceStart: Int? {
        guard case let .byteRange(start, _) = self else { return nil }
        return start
    }

    var sourceEnd: Int? {
        guard case let .byteRange(_, end) = self else { return nil }
        return end
    }
}

private func approximateTokenCount(in text: String) -> Int {
    attachmentRAGTokenize(text).count
}

private func stablePositiveStorageVersion(_ value: String) -> Int {
    let digest = attachmentRAGStableDigest(value)
    let prefix = digest.prefix(16)
    let raw = UInt64(prefix, radix: 16) ?? 1
    let version = Int(raw & 0x7FFF_FFFF_FFFF_FFFF)
    return max(version, 1)
}
