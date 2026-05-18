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

    @State private var sidebarSelection: SidebarSelection = .default
    @State private var accounts: [AccountRecord] = []
    @State private var threadScrollProxy: ScrollViewProxy?
    @AppStorage("pam.preferredLanguage") private var preferredLanguage: String = ""
    @AppStorage("pam.autoTranslate") private var autoTranslate: Bool = false
    @AppStorage("pam.defaultTone") private var defaultToneRaw: String = "warm"
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
                onToggleBrief: { withAnimation { briefCollapsed.toggle() } }
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
                        selection: $sidebarSelection
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
                },
                reading: {
                    ThreadView(
                        store: threadStore,
                        onArchive: { archiveSelectedThread() },
                        onStar: { starSelectedThread() },
                        showTranslated: translationStore.showTranslated,
                        translatedTexts: translationStore.translatedTexts,
                        translatedNodes: translationStore.translatedNodes,
                        onScrollProxy: { proxy in
                            threadScrollProxy = proxy
                        },
                        onTextNodesExtracted: { messageId, nodes in
                            _ = translationStore.nextGeneration(for: messageId)
                            translationStore.setExtractedNodes(
                                for: messageId,
                                nodes: nodes.map { ($0.id, $0.text) }
                            )
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
        .onChange(of: sidebarSelection) { _, newSelection in
            inboxStore.setSelection(newSelection)
            if case .account(let accountId) = newSelection {
                composition.activeAccountID = accountId
            }
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
        .keyboardShortcut(key: "k", modifiers: .command) {
            composition.showActionSheet.toggle()
        }
        .keyboardShortcut(key: "e", modifiers: .control) {
            archiveSelectedThread()
        }
        .keyboardShortcut(key: "s", modifiers: .control) {
            starSelectedThread()
        }
        .keyboardShortcut(key: "k", modifiers: .control) {
            markReadSelectedThread()
        }
        .keyboardShortcut(key: "r", modifiers: [.command, .shift]) {
            draftReply()
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

    // MARK: - Translation Helpers

    private func lastIncomingText() -> String? {
        if let lastIncoming = threadStore.messages.last(where: { !$0.isSentByMe }) {
            return lastIncoming.bestPlainText
        }
        return threadStore.messages.last?.bestPlainText
    }

    private func detectThreadLanguage() -> String? {
        guard let text = lastIncomingText() else { return nil }
        return translationStore.detect(text: text)
    }

    private func detectReplyLanguage() -> String? {
        guard let text = lastIncomingText(), !text.isEmpty else {
            return preferredLanguage.isEmpty ? nil : preferredLanguage
        }
        guard let result = translationStore.detectWithConfidence(text: text),
              result.confidence >= 0.5 else {
            return preferredLanguage.isEmpty ? nil : preferredLanguage
        }
        return result.language
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

// MARK: - Keyboard shortcut helper

private extension View {
    func keyboardShortcut(key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut(key, modifiers: modifiers)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }
}
