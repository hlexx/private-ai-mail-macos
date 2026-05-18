import Foundation
import GRDB

public struct ThreadBriefRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "thread_brief"

    public var accountId: String
    public var threadId: String
    public var latestMessageId: String
    public var summary: String?
    public var request: String?
    public var deadline: String?
    public var risk: String?
    public var nextStep: String?
    public var confidence: Double
    public var evidenceJson: String
    public var language: String?
    public var generatedAt: Int

    public init(
        accountId: String,
        threadId: String,
        latestMessageId: String,
        summary: String? = nil,
        request: String? = nil,
        deadline: String? = nil,
        risk: String? = nil,
        nextStep: String? = nil,
        confidence: Double = 0,
        evidenceJson: String = "[]",
        language: String? = nil,
        generatedAt: Int
    ) {
        self.accountId = accountId
        self.threadId = threadId
        self.latestMessageId = latestMessageId
        self.summary = summary
        self.request = request
        self.deadline = deadline
        self.risk = risk
        self.nextStep = nextStep
        self.confidence = confidence
        self.evidenceJson = evidenceJson
        self.language = language
        self.generatedAt = generatedAt
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case threadId = "thread_id"
        case latestMessageId = "latest_message_id"
        case summary, request, deadline, risk
        case nextStep = "next_step"
        case confidence
        case evidenceJson = "evidence_json"
        case language
        case generatedAt = "generated_at"
    }
}
