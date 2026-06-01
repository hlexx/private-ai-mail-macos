import Foundation
import GRDB

public struct ActionAttemptRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "action_attempt"

    public var opId: String
    public var attemptNumber: Int
    public var status: String
    public var startedAt: Int
    public var completedAt: Int?
    public var retryable: Int
    public var errorCode: String?
    public var errorMessage: String?

    public init(
        opId: String,
        attemptNumber: Int,
        status: String,
        startedAt: Int,
        completedAt: Int? = nil,
        retryable: Int = 0,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.opId = opId
        self.attemptNumber = attemptNumber
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.retryable = retryable
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case opId = "op_id"
        case attemptNumber = "attempt_number"
        case status
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case retryable
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}
