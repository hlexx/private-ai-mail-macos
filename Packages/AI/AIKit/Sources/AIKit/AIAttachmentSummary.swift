import Foundation

public struct AIAttachmentSummaryInput: Sendable, Equatable {
    public let filename: String
    public let mime: String
    public let chunks: [Chunk]

    public init(filename: String, mime: String, chunks: [Chunk]) {
        self.filename = filename
        self.mime = mime
        self.chunks = chunks
    }

    public struct Chunk: Sendable, Equatable {
        public let index: Int
        public let sourceOffset: Int
        public let text: String

        public init(index: Int, sourceOffset: Int, text: String) {
            self.index = index
            self.sourceOffset = sourceOffset
            self.text = text
        }
    }
}

public struct AIKeyField: Sendable, Equatable, Codable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct AIAttachmentEvidence: Sendable, Equatable, Codable {
    public let chunkIndex: Int
    public let quote: String

    public init(chunkIndex: Int, quote: String) {
        self.chunkIndex = chunkIndex
        self.quote = quote
    }
}

public struct AIAttachmentSummary: Sendable, Equatable, Codable {
    public let summary: String
    public let keyFields: [AIKeyField]
    public let risks: [String]
    public let nextSteps: [String]
    public let evidence: [AIAttachmentEvidence]
    public let confidence: Double

    public init(
        summary: String,
        keyFields: [AIKeyField] = [],
        risks: [String] = [],
        nextSteps: [String] = [],
        evidence: [AIAttachmentEvidence] = [],
        confidence: Double
    ) {
        self.summary = summary
        self.keyFields = keyFields
        self.risks = risks
        self.nextSteps = nextSteps
        self.evidence = evidence
        self.confidence = confidence
    }
}
