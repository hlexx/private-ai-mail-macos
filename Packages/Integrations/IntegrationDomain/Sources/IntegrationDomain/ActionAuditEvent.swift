import Foundation

public struct ActionAuditEvent: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Hashable, Sendable {
        case created
        case approvalRequested
        case approved
        case rejected
        case expired
        case queued
        case executionStarted
        case executionSucceeded
        case executionFailed
        case cancelled
        case blocked
    }

    public enum ActorKind: String, CaseIterable, Codable, Hashable, Sendable {
        case user
        case system
        case policy
        case executor
    }

    public let opId: String
    public let kind: Kind
    public let actor: ActorKind
    public let occurredAt: Date
    public let metadata: JSONValue

    public init(
        opId: String,
        kind: Kind,
        actor: ActorKind,
        occurredAt: Date,
        metadata: JSONValue = .object([:])
    ) {
        self.opId = opId
        self.kind = kind
        self.actor = actor
        self.occurredAt = occurredAt
        self.metadata = metadata
    }
}
