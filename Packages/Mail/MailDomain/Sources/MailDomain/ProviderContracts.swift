import Foundation

public struct MailProviderIdentifier: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static let gmail = MailProviderIdentifier(rawValue: "gmail")

    /// Microsoft Graph-backed Outlook provider persisted as `outlook`.
    public static let outlook = MailProviderIdentifier(rawValue: "outlook")

    /// Alias kept for code that uses Graph naming.
    public static let microsoftGraph = MailProviderIdentifier.outlook

    public var isTrustMVPSupported: Bool {
        self == .gmail || self == .outlook
    }

    public var displayName: String {
        switch self {
        case .gmail:
            return "Gmail"
        case .outlook:
            return "Outlook"
        default:
            return rawValue
        }
    }
}

public enum CanonicalMailboxUserDefinedKind: String, Codable, Sendable, Hashable {
    case label
    case category
}

public enum CanonicalMailbox: Sendable, Hashable {
    case inbox
    case sent
    case drafts
    case trash
    case spam
    case archive
    case starred
    case flagged
    case userDefined(id: String, name: String?, kind: CanonicalMailboxUserDefinedKind)
}

public enum GmailMailboxMapper {
    /// Gmail labels are many-to-many. A thread/message is archived when `INBOX`
    /// is absent, not by a dedicated archive label.
    public static func canonicalMailbox(forLabelID labelID: String, name: String? = nil) -> CanonicalMailbox {
        switch labelID {
        case "INBOX":
            return .inbox
        case "SENT":
            return .sent
        case "DRAFT":
            return .drafts
        case "TRASH":
            return .trash
        case "SPAM":
            return .spam
        case "STARRED":
            return .starred
        default:
            return .userDefined(id: labelID, name: name, kind: .label)
        }
    }

    public static func gmailLabelID(for mailbox: CanonicalMailbox) -> String? {
        switch mailbox {
        case .inbox:
            return "INBOX"
        case .sent:
            return "SENT"
        case .drafts:
            return "DRAFT"
        case .trash:
            return "TRASH"
        case .spam:
            return "SPAM"
        case .starred:
            return "STARRED"
        case .archive:
            return nil
        case .flagged:
            return nil
        case let .userDefined(id, _, kind):
            return kind == .label ? id : nil
        }
    }

    /// Archive in Gmail means "not in INBOX" while keeping any other labels.
    public static func isArchived(labelIDs: [String]) -> Bool {
        !labelIDs.contains("INBOX")
    }
}

public enum GraphMailboxMapper {
    /// Graph folders are hierarchical; canonical archive maps to Archive folder
    /// or equivalent move behavior. Categories are metadata and are modeled as
    /// user-defined category mailboxes.
    public static func canonicalMailbox(forWellKnownFolder folderName: String, folderID: String? = nil) -> CanonicalMailbox {
        switch folderName.lowercased() {
        case "inbox":
            return .inbox
        case "sentitems":
            return .sent
        case "drafts":
            return .drafts
        case "deleteditems":
            return .trash
        case "junkemail":
            return .spam
        case "archive":
            return .archive
        default:
            return .userDefined(id: folderID ?? folderName, name: folderName, kind: .label)
        }
    }

    public static func graphWellKnownFolder(for mailbox: CanonicalMailbox) -> String? {
        switch mailbox {
        case .inbox:
            return "inbox"
        case .sent:
            return "sentitems"
        case .drafts:
            return "drafts"
        case .trash:
            return "deleteditems"
        case .spam:
            return "junkemail"
        case .archive:
            return "archive"
        case .starred:
            return nil
        case .flagged:
            return nil
        case .userDefined:
            return nil
        }
    }

    public static func canonicalCategory(name: String) -> CanonicalMailbox {
        .userDefined(id: name, name: name, kind: .category)
    }

    /// Graph flagged state is separate from categories/folders.
    public static func canonicalFlaggedMailbox(isFlagged: Bool) -> CanonicalMailbox? {
        isFlagged ? .flagged : nil
    }
}
