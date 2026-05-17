import Foundation

public enum SidebarSelection: Hashable, Sendable {
    case folder(FolderID)
    case account(String)

    public static let `default`: SidebarSelection = .folder(.inbox)
}

public enum FolderID: String, Hashable, Sendable, CaseIterable {
    case inbox
    case needsReply = "reply"
    case hasDeadline = "due"
    case attachments = "att"
    case logged
    case starred
    case sent
    case archive = "arch"

    public var gmailLabel: String? {
        switch self {
        case .inbox: return "INBOX"
        case .sent: return "SENT"
        case .starred: return "STARRED"
        case .archive: return nil
        default: return nil
        }
    }
}
