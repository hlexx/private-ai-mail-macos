import ActionsFeature
import InboxFeature
import MailDomain
import Persistence
import SwiftUI

enum MainSceneActionRoute: Equatable {
    case draftReply
    case replyAll
    case forward
    case archiveSelectedThread
    case starSelectedThread
    case trashSelectedThread
    case markReadSelectedThread
    case markUnreadSelectedThread
    case threadNewer
    case threadOlder
    case folderInbox
    case folderStarred
    case folderSent
    case folderArchive
    case folderAll
    case pageDownOrNextUnread
    case focusSearch
    case toggleKeyboardHelp
    case composeSendHandledByComposeWindow
    case refresh
    case toggleActionSheet
    case newCompose
}

enum MainSceneActionSheetRoute: Equatable {
    case none
    case draftReply
    case trustAction(TrustMVPAction)
}

enum MainSceneActionRouter {
    // Mirrors the full keyboard catalog; keep this exhaustive so new shortcuts
    // must choose an app-shell route explicitly.
    // swiftlint:disable:next cyclomatic_complexity
    static func route(for key: ActionKey) -> MainSceneActionRoute {
        switch key {
        case .reply: .draftReply
        case .replyAll: .replyAll
        case .forward: .forward
        case .archive: .archiveSelectedThread
        case .star: .starSelectedThread
        case .trash: .trashSelectedThread
        case .markRead: .markReadSelectedThread
        case .markUnread: .markUnreadSelectedThread
        case .threadNewer: .threadNewer
        case .threadOlder: .threadOlder
        case .folderInbox: .folderInbox
        case .folderStarred: .folderStarred
        case .folderSent: .folderSent
        case .folderArchive: .folderArchive
        case .folderAll: .folderAll
        case .pageDownOrNextUnread: .pageDownOrNextUnread
        case .focusSearch: .focusSearch
        case .showHelp: .toggleKeyboardHelp
        case .sendCompose: .composeSendHandledByComposeWindow
        case .refresh: .refresh
        case .actionSheet: .toggleActionSheet
        case .newCompose: .newCompose
        }
    }

    static func route(actionSheetAction action: TrustMVPAction?) -> MainSceneActionSheetRoute {
        guard let action else { return .none }
        if action == .draftReply {
            return .draftReply
        }
        return .trustAction(action)
    }
}

// Keyboard, toolbar, and action-sheet dispatch translate app-shell commands into
// the same mutation helpers. Keep provider writes behind MainSceneMutations.
extension MainScene {
    var actionSheetExecutionAvailability: ActionExecutionAvailability {
        Self.actionSheetExecutionAvailability(
            selectedThreadID: inboxStore.selectedThreadID,
            threads: inboxStore.threads,
            accounts: accounts
        )
    }

    static func actionSheetExecutionAvailability(
        selectedThreadID: String?,
        threads: [ThreadRow],
        accounts: [AccountRecord]
    ) -> ActionExecutionAvailability {
        guard let threadId = selectedThreadID,
              let thread = threads.first(where: { $0.id == threadId }),
              let account = accounts.first(where: { $0.id == thread.accountId }),
              account.provider == MailProviderIdentifier.gmail.rawValue else {
            return .unsupportedProvider
        }
        return .supported
    }

    func handleActionSheet(_ action: TrustMVPAction?) {
        switch MainSceneActionRouter.route(actionSheetAction: action) {
        case .none:
            return
        case .draftReply:
            draftReply()
        case .trustAction(let trustAction):
            requestTrustActionForSelectedThread(trustAction)
        }
    }

    func wireDispatcher() {
        keyboardDispatcher.actionHandler = { [self] actionKey in
            handleAction(actionKey)
        }
    }

    func handleAction(_ key: ActionKey) {
        execute(MainSceneActionRouter.route(for: key))
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func execute(_ route: MainSceneActionRoute) {
        switch route {
        case .draftReply:
            draftReply()
        case .replyAll:
            replyAll()
        case .forward:
            forwardThread()
        case .archiveSelectedThread:
            archiveSelectedThread()
        case .starSelectedThread:
            starSelectedThread()
        case .trashSelectedThread:
            trashSelectedThread()
        case .markReadSelectedThread:
            markReadSelectedThread()
        case .markUnreadSelectedThread:
            markUnreadSelectedThread()
        case .threadNewer:
            navigateThread(direction: .newer)
        case .threadOlder:
            navigateThread(direction: .older)
        case .folderInbox:
            jumpToFolder(.folder(.inbox))
        case .folderStarred:
            jumpToFolder(.folder(.starred))
        case .folderSent:
            jumpToFolder(.folder(.sent))
        case .folderArchive:
            jumpToFolder(.folder(.archive))
        case .folderAll:
            jumpToFolder(.allAccountsAllFolders)
        case .pageDownOrNextUnread:
            pageDownOrNextUnread()
        case .focusSearch:
            searchFocused = true
        case .toggleKeyboardHelp:
            keyboardDispatcher.showKeyboardHelp.toggle()
        case .composeSendHandledByComposeWindow:
            return
        case .refresh:
            refreshCurrentAccount()
        case .toggleActionSheet:
            composition.showActionSheet.toggle()
        case .newCompose:
            prepareNewCompose()
            composition.showCompose = true
        }
    }

    func trashSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        trashThread(threadId, accountId: thread.accountId)
    }

    func markUnreadSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        Task {
            do {
                try await composition.mailMutator.markRead(threadId, accountId: accountId, read: false)
                showToast("Marked unread", undo: nil)
            } catch {
                showMutationError(error, fallback: "Mark unread failed")
            }
        }
    }

    func refreshCurrentAccount() {
        if let selected = inboxStore.selectedThreadID,
           let thread = inboxStore.threads.first(where: { $0.id == selected }) {
            composition.refreshAccount(thread.accountId)
        } else {
            composition.refreshAllAccounts()
        }
    }

    func updateTextInputFocusState() {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            keyboardDispatcher.isTextInputFocused = false
            return
        }
        keyboardDispatcher.isTextInputFocused = responder is NSTextView || responder is NSTextField
    }
}
