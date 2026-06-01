import Foundation

public struct ActionResult: Codable, Equatable, Hashable, Sendable {
    public let schemaVersion: Int
    public let status: ActionStatus
    public let externalResultId: String?
    public let failureKind: ActionFailureKind?
    public let completedAt: Date?
    public let metadata: JSONValue

    public init(
        schemaVersion: Int = ActionPayload.currentSchemaVersion,
        status: ActionStatus,
        externalResultId: String? = nil,
        failureKind: ActionFailureKind? = nil,
        completedAt: Date? = nil,
        metadata: JSONValue = .object([:])
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.externalResultId = externalResultId
        self.failureKind = failureKind
        self.completedAt = completedAt
        self.metadata = metadata
    }
}
