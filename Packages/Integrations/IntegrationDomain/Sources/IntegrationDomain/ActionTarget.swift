import Foundation

public enum ActionTargetKind: String, CaseIterable, Codable, Hashable, Sendable {
    case thread
    case message
    case attachment
    case integrationDestination
}

public enum IntegrationDestinationKind: String, CaseIterable, Codable, Hashable, Sendable {
    case slack
    case notion
    case crm
}

public enum ActionTarget: Codable, Equatable, Hashable, Sendable {
    case thread(accountId: String, threadId: String)
    case message(accountId: String, threadId: String, messageId: String)
    case attachment(accountId: String, messageId: String, attachmentId: String)
    case integrationDestination(
        accountId: String,
        destinationKind: IntegrationDestinationKind,
        destinationId: String
    )

    public var accountId: String {
        switch self {
        case let .thread(accountId, _),
             let .message(accountId, _, _),
             let .attachment(accountId, _, _),
             let .integrationDestination(accountId, _, _):
            accountId
        }
    }

    public var kind: ActionTargetKind {
        switch self {
        case .thread:
            .thread
        case .message:
            .message
        case .attachment:
            .attachment
        case .integrationDestination:
            .integrationDestination
        }
    }

    var stableComponents: [String] {
        switch self {
        case let .thread(accountId, threadId):
            [kind.rawValue, accountId, threadId]
        case let .message(accountId, threadId, messageId):
            [kind.rawValue, accountId, threadId, messageId]
        case let .attachment(accountId, messageId, attachmentId):
            [kind.rawValue, accountId, messageId, attachmentId]
        case let .integrationDestination(accountId, destinationKind, destinationId):
            [kind.rawValue, accountId, destinationKind.rawValue, destinationId]
        }
    }
}
