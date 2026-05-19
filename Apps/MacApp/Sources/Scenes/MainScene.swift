import ActionsFeature
import BriefFeature
import ComposeFeature
import DesignSystem
import GRDB
import InboxFeature
import MailDomain
import Persistence
import SwiftUI
import ThreadFeature
import TranslationFeature

struct MainScene: View {

    let composition: CompositionRoot
    let keyboardDispatcher: KeyboardDispatcher

    @State private var sidebarSelection: SidebarSelection = .default
    @State var threadListWrapPulse: Bool = false
    @State private var folderJumpPulse: SidebarSelection?
    // keyboardDispatcher.showKeyboardHelp lives on keyboardDispatcher so the app-level Help menu can toggle it too
    @FocusState private var searchFocused: Bool
    @State var accounts: [AccountRecord] = []
    // NOTE — these three were declared `private` initially; relaxed to
    // internal so MainSceneMutations (separate file in same target)
    // can read them when dispatching mutations.
    @State var threadScrollProxy: ScrollViewProxy?
    @AppStorage("pam.preferredLanguage") var preferredLanguage: String = ""
    @AppStorage("pam.autoTranslate") private var autoTranslate: Bool = false
    @AppStorage("pam.defaultTone") var defaultToneRaw: String = "warm"
    @AppStorage("pam.layout.sidebar") private var sidebarWidth: Double = Double(RBLayout.sidebarWidth)
    @AppStorage("pam.layout.threadlist") private var threadlistWidth: Double = Double(RBLayout.threadListWidth)
    @AppStorage("pam.layout.brief") private var briefWidth: Double = Double(RBLayout.briefRailWidth)
    @AppStorage("pam.layout.sidebarCollapsed") private var sidebarCollapsed: Bool = false
    @AppStorage("pam.layout.briefCollapsed") private var briefCollapsed: Bool = false
    @Environment(\.openSettings) private var openSettings

    var inboxStore: InboxStore { composition.inboxStore }
    var threadStore: ThreadStore { composition.threadStore }
    var briefStore: BriefStore { composition.briefStore }
    var translationStore: TranslationStore { composition.translationStore }

    var body: some View {
        VStack(spacing: 0) {
            RBToolbar(
                accounts: accounts,
                activeAccountID: composition.activeAccountID,
                onCycleAccount: { composition.cycleActiveAccount(accounts: accounts) },
                onToggleTheme: { toggleTheme() },
                onOpenSettings: { openSettings() },
                onCompose: {
                    prepareNewCompose()
                    composition.showCompose = true
                },
                onOpenActionSheet: { composition.showActionSheet = true },
                onToggleSidebar: { withAnimation { sidebarCollapsed.toggle() } },
                onToggleBrief: { withAnimation { briefCollapsed.toggle() } },
                sidebarWidth: CGFloat(sidebarWidth),
                sidebarCollapsed: sidebarCollapsed,
                searchFocused: $searchFocused
            )

            MainSplitController(
                sidebarCollapsed: $sidebarCollapsed,
                briefCollapsed: $briefCollapsed,
                sidebarWidth: $sidebarWidth,
                threadlistWidth: $threadlistWidth,
                briefWidth: $briefWidth,
                sidebar: {
                    RBSidebar(
                        folders: sidebarFolders,
                        accounts: accounts.map { AccountRow(account: $0) },
                        selection: $sidebarSelection,
                        jumpPulse: folderJumpPulse
                    )
                },
                threadlist: {
                    InboxView(
                        store: inboxStore,
                        onArchive: { threadId, accountId in
                            Task {
                                do {
                                    try await composition.mailMutator.archive(threadId, accountId: accountId)
                                    showToast("Archived", undo: .unarchive(threadId: threadId, accountId: accountId))
                                } catch {
                                    showToast("Archive failed", undo: nil)
                                }
                            }
                        },
                        onTrash: { threadId, accountId in
                            trashThread(threadId, accountId: accountId)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.rbAccent.opacity(threadListWrapPulse ? 0.6 : 0), lineWidth: 2)
                    )
                    .animation(.easeOut(duration: 0.18), value: threadListWrapPulse)
                },
                reading: {
                    ThreadView(
                        store: threadStore,
                        onArchive: { archiveSelectedThread() },
                        onStar: { starSelectedThread() },
                        showTranslated: translationStore.showTranslated,
                        translatedTexts: translationStore.translatedTexts,
                        translatedNodes: translationStore.translatedNodes,
                        onTextNodesExtracted: { messageId, nodes in
                            _ = translationStore.nextGeneration(for: messageId)
                            // Clear stale node translations so re-extraction
                            // (e.g. after toggling remote images) triggers fresh translation
                            translationStore.clearNodeTranslations(for: messageId)
                            translationStore.setExtractedNodes(
                                for: messageId,
                                nodes: nodes.map { ($0.id, $0.text) }
                            )
                            // Re-trigger translation if the toggle is already active.
                            // translateAll may have run before extraction finished,
                            // so newly extracted nodes need a fresh translation pass.
                            if translationStore.showTranslated {
                                translationStore.needsRetranslation = true
                            }
                        },
                        onScrollProxy: { proxy in
                            threadScrollProxy = proxy
                        },
                        composer: {
                            if let threadID = inboxStore.selectedThreadID, briefStore.brief != nil {
                                InlineComposer(
                                    threadID: threadID,
                                    accountId: inboxStore.threads.first(where: { $0.id == threadID })?.accountId,
                                    replyLanguage: detectReplyLanguage(),
                                    replyStore: composition.replyStore,
                                    onEditInFull: { draftText in
                                        prefillComposeForReply()
                                        composition.composeViewModel.bodyText = draftText
                                        composition.showCompose = true
                                    },
                                    onSend: { bodyText in
                                        prefillComposeForReply()
                                        composition.composeViewModel.bodyText = bodyText
                                        composition.composeViewModel.requestSend()
                                    }
                                )
                            }
                        },
                        translationHeader: {
                            TranslationToggleView(
                                store: translationStore,
                                detectedLanguage: detectThreadLanguage(),
                                preferredLanguage: preferredLanguage,
                                autoTranslate: autoTranslate,
                                messages: threadStore.messages.map { ($0.id, $0.bestPlainText) },
                                htmlMessageIds: Set(threadStore.messages.compactMap { $0.bodyHtml != nil ? $0.id : nil })
                            )
                        }
                    )
                },
                brief: {
                    BriefRail(store: briefStore, onDraftReply: { draftReply() })
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            )
        }
        // Extend our 56pt RBToolbar all the way to the top of the window,
        // under the (transparent) titlebar / traffic-light zone. Without
        // this, SwiftUI keeps a ~28pt top safe-area inset reserved for the
        // titlebar and the visible chrome ends up ~84pt tall.
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.rbBgDeep)
        .overlay {
            if composition.showActionSheet {
                ActionSheetView(
                    threadSubject: threadStore.subject.isEmpty ? String(localized: "action.fallbackSubject", defaultValue: "Selected thread") : threadStore.subject,
                    onAction: { _ in
                        composition.showActionSheet = false
                    }
                )
            }
        }
        .overlay {
            if keyboardDispatcher.showKeyboardHelp {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { keyboardDispatcher.showKeyboardHelp = false }
                KeyboardHelpOverlay(isPresented: Bindable(keyboardDispatcher).showKeyboardHelp)
            }
        }
        .onChange(of: sidebarSelection) { _, newSelection in
            inboxStore.setSelection(newSelection)
            if case .account(let accountId) = newSelection {
                composition.activeAccountID = accountId
            }
        }
        .onChange(of: preferredLanguage) { _, _ in
            translationStore.clearCache()
        }
        .onChange(of: inboxStore.selectedThreadID) { _, newValue in
            translationStore.clearCache()
            if let threadId = newValue,
               let thread = inboxStore.threads.first(where: { $0.id == threadId }) {
                let accountEmail = accounts.first(where: { $0.id == thread.accountId })?.email ?? ""
                threadStore.accountEmail = accountEmail
                threadStore.observe(threadId: threadId, accountId: thread.accountId)
                briefStore.loadBrief(forThreadID: threadId, accountId: thread.accountId)
            } else {
                threadStore.stopObserving()
                briefStore.loadBrief(forThreadID: nil)
            }
        }
        .task {
            await observeAccounts()
        }
        .mailKeyboardShortcuts(dispatcher: keyboardDispatcher)
        .onAppear { wireDispatcher() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            updateTextInputFocusState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didBeginEditingNotification)) { _ in
            keyboardDispatcher.isTextInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didEndEditingNotification)) { _ in
            updateTextInputFocusState()
        }
        .overlay(alignment: .bottom) {
            if let toast = composition.toastMessage {
                toastBar(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: composition.toastMessage)
    }

    private var sidebarFolders: [FolderItem] {
        var folders = FolderItem.defaultFolders
        let counts = inboxStore.folderCounts
        for idx in folders.indices {
            let c = counts[folders[idx].id]
            folders[idx].count = (c ?? 0) > 0 ? c : nil
        }
        return folders
    }

    // MARK: - Compose Helpers

    private func prepareNewCompose() {
        let vm = composition.composeViewModel
        vm.reset()
        vm.accounts = accounts.map { AccountInfo(id: $0.id, email: $0.email, displayName: $0.displayName) }
        if let activeID = composition.activeAccountID ?? accounts.first?.id {
            vm.selectedAccountID = activeID
            vm.selectedAccountEmail = accounts.first(where: { $0.id == activeID })?.email
        }
    }

    private func prefillComposeForReply() {
        let vm = composition.composeViewModel
        vm.reset()
        guard let lastMessage = threadStore.messages.last else { return }

        // For To: field, find the last message NOT sent by the user so we
        // reply to the other party. For sent-only threads, use the toAddr
        // of the last message (the original recipient).
        let replyTarget = threadStore.messages.last(where: { !$0.isSentByMe })
        let replyToAddr: String
        if let target = replyTarget {
            replyToAddr = extractEmail(from: target.fromAddr)
        } else {
            replyToAddr = extractEmail(from: lastMessage.toAddr)
        }

        // For In-Reply-To, always use the absolute last message in the
        // thread so threading headers stay correct even when we send
        // multiple replies in a row.
        let inReplyToID = lastMessage.messageIdHeader ?? lastMessage.id

        // Build the References chain from all messages' Message-ID headers
        // so the outgoing reply preserves the full thread ancestry.
        let referencesChain = threadStore.messages.compactMap(\.messageIdHeader)

        // Bind to the thread's account, not the toolbar-global active account,
        // so multi-account sessions always reply from the correct mailbox.
        let threadAccountId = inboxStore.threads.first(where: { $0.id == lastMessage.threadId })?.accountId
        let replyAccountId = threadAccountId ?? composition.activeAccountID
        let replyAccountEmail = accounts.first(where: { $0.id == replyAccountId })?.email

        vm.prefillReply(
            fromAddr: replyToAddr,
            subject: threadStore.subject,
            threadID: lastMessage.threadId,
            lastMessageID: inReplyToID,
            referencesChain: referencesChain
        )
        vm.accounts = accounts.map { AccountInfo(id: $0.id, email: $0.email, displayName: $0.displayName) }
        if let accountID = replyAccountId {
            vm.selectedAccountID = accountID
            vm.selectedAccountEmail = replyAccountEmail
        }
    }

}

// MARK: - Helpers

extension MainScene {
    func extractEmail(from addr: String?) -> String {
        guard let addr else { return "" }
        if let open = addr.firstIndex(of: "<"),
           let close = addr.firstIndex(of: ">"),
           close > open {
            return String(addr[addr.index(after: open)..<close])
        }
        return addr.trimmingCharacters(in: .whitespaces)
    }

    func observeAccounts() async {
        let observation = ValueObservation.tracking { db in
            try AccountRecord.fetchAll(db)
        }
        do {
            for try await records in observation.values(in: composition.db.dbQueue) {
                self.accounts = records
                if composition.activeAccountID == nil, let first = records.first {
                    composition.activeAccountID = first.id
                }
            }
        } catch {
            // Observation ended
        }
    }
}

// MARK: - Keyboard Dispatcher Wiring

extension MainScene {
    func wireDispatcher() {
        keyboardDispatcher.actionHandler = { [self] actionKey in
            handleAction(actionKey)
        }
    }

    private func handleAction(_ key: ActionKey) {
        switch key {
        case .reply:
            draftReply()
        case .replyAll:
            replyAll()
        case .forward:
            forwardThread()
        case .archive:
            archiveSelectedThread()
        case .star:
            starSelectedThread()
        case .trash:
            trashSelectedThread()
        case .markRead:
            markReadSelectedThread()
        case .markUnread:
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
        case .showHelp:
            keyboardDispatcher.showKeyboardHelp.toggle()
        case .sendCompose:
            break // Handled by ComposeWindowView directly
        case .newCompose:
            prepareNewCompose()
            composition.showCompose = true
        case .refresh:
            refreshCurrentAccount()
        case .actionSheet:
            composition.showActionSheet.toggle()
        }
    }

    private func jumpToFolder(_ target: SidebarSelection) {
        sidebarSelection = target
        folderJumpPulse = target
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            folderJumpPulse = nil
        }
    }

    private func trashSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        trashThread(threadId, accountId: thread.accountId)
    }

    private func markUnreadSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        Task {
            do {
                try await composition.mailMutator.markRead(threadId, accountId: accountId, read: false)
                showToast("Marked unread", undo: nil)
            } catch {
                showToast("Mark unread failed", undo: nil)
            }
        }
    }

    private func refreshCurrentAccount() {
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
