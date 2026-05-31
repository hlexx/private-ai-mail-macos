import Foundation

public enum ActionKind: String, CaseIterable, Codable, Hashable, Sendable {
    case draftReply
    case sendReply
    case archiveThread
    case starThread
    case markRead
    case trashThread
    case snoozeThread
    case sendToSlack
    case createNotionPage
    case logToCRM

    public var isLocalLowRisk: Bool {
        switch self {
        case .draftReply, .archiveThread, .starThread, .markRead, .snoozeThread:
            true
        case .sendReply, .trashThread, .sendToSlack, .createNotionPage, .logToCRM:
            false
        }
    }

    public var requiresSendApproval: Bool {
        self == .sendReply
    }

    public var isExternalWrite: Bool {
        switch self {
        case .sendToSlack, .createNotionPage, .logToCRM:
            true
        case .draftReply, .sendReply, .archiveThread, .starThread, .markRead, .trashThread, .snoozeThread:
            false
        }
    }

    public var isDestructive: Bool {
        self == .trashThread
    }
}
