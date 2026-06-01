import Foundation
import MailDomain

public enum SidebarSelection: Hashable, Sendable {
    case folder(FolderID)
    case account(String)
    case allAccountsAllFolders

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
    case trash
    case spam
    case archive = "arch"

    public var canonicalMailbox: CanonicalMailbox? {
        switch self {
        case .inbox: return .inbox
        case .sent: return .sent
        case .starred: return .starred
        case .trash: return .trash
        case .spam: return .spam
        case .archive: return .archive
        case .needsReply, .hasDeadline, .attachments, .logged:
            return nil
        }
    }

    public var gmailLabel: String? {
        canonicalMailbox.flatMap(GmailMailboxMapper.gmailLabelID(for:))
    }
}
