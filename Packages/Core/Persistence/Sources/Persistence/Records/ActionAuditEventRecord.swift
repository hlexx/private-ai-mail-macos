import Foundation
import GRDB

public struct ActionAuditEventRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "action_audit_event"

    public var eventId: String
    public var opId: String
    public var eventKind: String
    public var actorKind: String
    public var occurredAt: Int
    public var metadataJSON: String

    public init(
        eventId: String,
        opId: String,
        eventKind: String,
        actorKind: String,
        occurredAt: Int,
        metadataJSON: String = "{}"
    ) {
        self.eventId = eventId
        self.opId = opId
        self.eventKind = eventKind
        self.actorKind = actorKind
        self.occurredAt = occurredAt
        self.metadataJSON = metadataJSON
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case opId = "op_id"
        case eventKind = "event_kind"
        case actorKind = "actor_kind"
        case occurredAt = "occurred_at"
        case metadataJSON = "metadata_json"
    }
}
