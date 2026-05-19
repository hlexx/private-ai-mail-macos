import AppKit
import SwiftUI

// MARK: - Keyboard Section

enum KeyboardSection: String, CaseIterable {
    case mail, navigation, compose, view

    var title: String {
        switch self {
        case .mail: "Mail"
        case .navigation: "Navigation"
        case .compose: "Compose"
        case .view: "View"
        }
    }
}

// MARK: - Shortcut Scope

enum ShortcutScope: String {
    case global
    case threadlist
    case reading
    case compose
}

// MARK: - Action Key

enum ActionKey: String, CaseIterable {
    case reply, replyAll, forward
    case archive, star, trash, markRead, markUnread
    case threadNewer, threadOlder
    case folderInbox, folderStarred, folderSent, folderArchive, folderAll
    case pageDownOrNextUnread, focusSearch, showHelp, sendCompose
    case newCompose, refresh, actionSheet
}

// MARK: - Shortcut Spec

struct ShortcutSpec: Identifiable {
    let id: String
    let section: KeyboardSection
    let label: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let scope: ShortcutScope
    let requiresInputBlur: Bool
    let actionKey: ActionKey
    let deprecated: Bool

    init(
        id: String,
        section: KeyboardSection,
        label: String,
        key: KeyEquivalent,
        modifiers: EventModifiers = [],
        scope: ShortcutScope = .global,
        requiresInputBlur: Bool = false,
        actionKey: ActionKey,
        deprecated: Bool = false
    ) {
        self.id = id
        self.section = section
        self.label = label
        self.key = key
        self.modifiers = modifiers
        self.scope = scope
        self.requiresInputBlur = requiresInputBlur
        self.actionKey = actionKey
        self.deprecated = deprecated
    }
}

// MARK: - Catalog

extension ShortcutSpec {
    static let all: [ShortcutSpec] = [
        // MARK: Mail
        ShortcutSpec(
            id: "mail.reply",
            section: .mail, label: "Reply",
            key: "r", modifiers: .command,
            actionKey: .reply
        ),
        ShortcutSpec(
            id: "mail.reply.bare",
            section: .mail, label: "Reply",
            key: "r",
            requiresInputBlur: true,
            actionKey: .reply
        ),
        ShortcutSpec(
            id: "mail.replyAll",
            section: .mail, label: "Reply All",
            key: "r", modifiers: [.command, .shift],
            actionKey: .replyAll
        ),
        ShortcutSpec(
            id: "mail.replyAll.bare",
            section: .mail, label: "Reply All",
            key: "a",
            requiresInputBlur: true,
            actionKey: .replyAll
        ),
        ShortcutSpec(
            id: "mail.forward",
            section: .mail, label: "Forward",
            key: "f", modifiers: [.command, .option],
            actionKey: .forward
        ),
        ShortcutSpec(
            id: "mail.forward.bare",
            section: .mail, label: "Forward",
            key: "f",
            requiresInputBlur: true,
            actionKey: .forward
        ),
        ShortcutSpec(
            id: "mail.archive",
            section: .mail, label: "Archive",
            key: "e",
            requiresInputBlur: true,
            actionKey: .archive
        ),
        ShortcutSpec(
            id: "mail.archive.legacy",
            section: .mail, label: "Archive (legacy)",
            key: "e", modifiers: .control,
            actionKey: .archive,
            deprecated: true
        ),
        ShortcutSpec(
            id: "mail.star",
            section: .mail, label: "Star / Unstar",
            key: "s",
            requiresInputBlur: true,
            actionKey: .star
        ),
        ShortcutSpec(
            id: "mail.star.legacy",
            section: .mail, label: "Star (legacy)",
            key: "s", modifiers: .control,
            actionKey: .star,
            deprecated: true
        ),
        ShortcutSpec(
            id: "mail.trash",
            section: .mail, label: "Trash",
            key: "#",
            requiresInputBlur: true,
            actionKey: .trash
        ),
        ShortcutSpec(
            id: "mail.trash.cmd",
            section: .mail, label: "Trash",
            key: .delete, modifiers: .command,
            actionKey: .trash
        ),
        ShortcutSpec(
            id: "mail.markRead",
            section: .mail, label: "Mark Read",
            key: "i", modifiers: .shift,
            requiresInputBlur: true,
            actionKey: .markRead
        ),
        ShortcutSpec(
            id: "mail.markUnread",
            section: .mail, label: "Mark Unread",
            key: "u", modifiers: .shift,
            requiresInputBlur: true,
            actionKey: .markUnread
        ),

        // MARK: Navigation
        ShortcutSpec(
            id: "nav.threadOlder",
            section: .navigation, label: "Older Thread",
            key: "j",
            requiresInputBlur: true,
            actionKey: .threadOlder
        ),
        ShortcutSpec(
            id: "nav.threadNewer",
            section: .navigation, label: "Newer Thread",
            key: "k",
            requiresInputBlur: true,
            actionKey: .threadNewer
        ),
        ShortcutSpec(
            id: "nav.pageDown",
            section: .navigation, label: "Page Down / Next Unread",
            key: .space,
            requiresInputBlur: true,
            actionKey: .pageDownOrNextUnread
        ),
        ShortcutSpec(
            id: "nav.folderInbox",
            section: .navigation, label: "Go to Inbox",
            key: "1", modifiers: .command,
            actionKey: .folderInbox
        ),
        ShortcutSpec(
            id: "nav.folderStarred",
            section: .navigation, label: "Go to Starred",
            key: "2", modifiers: .command,
            actionKey: .folderStarred
        ),
        ShortcutSpec(
            id: "nav.folderSent",
            section: .navigation, label: "Go to Sent",
            key: "3", modifiers: .command,
            actionKey: .folderSent
        ),
        ShortcutSpec(
            id: "nav.folderArchive",
            section: .navigation, label: "Go to Archive",
            key: "4", modifiers: .command,
            actionKey: .folderArchive
        ),
        ShortcutSpec(
            id: "nav.folderAll",
            section: .navigation, label: "All Accounts",
            key: "5", modifiers: .command,
            actionKey: .folderAll
        ),
        ShortcutSpec(
            id: "nav.focusSearch",
            section: .navigation, label: "Focus Search",
            key: "l", modifiers: .command,
            actionKey: .focusSearch
        ),

        // MARK: Compose
        ShortcutSpec(
            id: "compose.new",
            section: .compose, label: "New Message",
            key: "n", modifiers: .command,
            actionKey: .newCompose
        ),
        ShortcutSpec(
            id: "compose.send",
            section: .compose, label: "Send",
            key: .return, modifiers: .command,
            scope: .compose,
            actionKey: .sendCompose
        ),

        // MARK: View
        ShortcutSpec(
            id: "view.refresh",
            section: .view, label: "Refresh",
            key: KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)),
            requiresInputBlur: true,
            actionKey: .refresh
        ),
        ShortcutSpec(
            id: "view.refresh.cmd",
            section: .view, label: "Refresh",
            key: "l", modifiers: [.command, .shift],
            actionKey: .refresh
        ),
        ShortcutSpec(
            id: "view.actionSheet",
            section: .view, label: "Action Sheet",
            key: "k", modifiers: .command,
            actionKey: .actionSheet
        ),
        ShortcutSpec(
            id: "view.showHelp",
            section: .view, label: "Keyboard Shortcuts",
            key: "?",
            requiresInputBlur: true,
            actionKey: .showHelp
        ),
    ]
}
