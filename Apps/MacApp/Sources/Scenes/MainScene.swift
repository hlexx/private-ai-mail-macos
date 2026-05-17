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
    @AppStorage("pam.preferredLanguage") private var preferredLanguage: String = "en"
    @Environment(\.openSettings) private var openSettings

    private var inboxStore: InboxStore { composition.inboxStore }
    private var threadStore: ThreadStore { composition.threadStore }
    private var briefStore: BriefStore { composition.briefStore }
    private var translationStore: TranslationStore { composition.translationStore }

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
                onOpenActionSheet: { composition.showActionSheet = true }
            )

            // HSplitView gives draggable column dividers between the three
            // panes (sidebar / threadlist / reading). Initial widths follow
            // the design tokens but the user can resize at runtime; min
            // values keep panes usable at small window sizes.
            HSplitView {
                RBSidebar(
                    folders: sidebarFolders,
                    accounts: accounts.map { AccountRow(account: $0) },
                    selection: $sidebarSelection
                )
                .frame(
                    minWidth: 180,
                    idealWidth: RBLayout.sidebarWidth,
                    maxWidth: 360,
                    maxHeight: .infinity,
                    alignment: .top
                )

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
                    .frame(
                        minWidth: 280,
                        idealWidth: RBLayout.threadListWidth,
                        maxWidth: 480,
                        maxHeight: .infinity,
                        alignment: .top
                    )

                ThreadView(
                    store: threadStore,
                    onArchive: { archiveSelectedThread() },
                    onStar: { starSelectedThread() },
                    composer: {
                        if let threadID = inboxStore.selectedThreadID, briefStore.brief != nil {
                            InlineComposer(
                                threadID: threadID,
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
                    briefRail: {
                        // Brief rail lives *inside* the reading pane per
                        // design/re-box/project/app/app.css `.rb-read-body`
                        // (grid 1fr / 340px). It sits beside the thread
                        // column, under the shared head — not as a 4th
                        // top-level pane.
                        BriefRail(store: briefStore)
                            .frame(width: RBLayout.briefRailWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                    },
                    translationHeader: {
                        TranslationToggleView(
                            store: translationStore,
                            detectedLanguage: detectThreadLanguage(),
                            preferredLanguage: preferredLanguage,
                            messages: threadStore.messages.map { ($0.id, $0.bodyText) }
                        )
                    }
                )
                .frame(
                    minWidth: 480,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }
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
                        // TODO(§15-step-4): handle selected action
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
                briefStore.loadBrief(forThreadID: threadId)
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
        .keyboardShortcut(key: "e", modifiers: []) {
            archiveSelectedThread()
        }
        .keyboardShortcut(key: "s", modifiers: []) {
            starSelectedThread()
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

    private func detectThreadLanguage() -> String? {
        guard let lastIncoming = threadStore.messages.last(where: { !$0.isSentByMe }) else {
            return threadStore.messages.last.flatMap { translationStore.detect(text: $0.bodyText) }
        }
        return translationStore.detect(text: lastIncoming.bodyText)
    }

    private func detectReplyLanguage() -> String? {
        let text: String
        if let lastIncoming = threadStore.messages.last(where: { !$0.isSentByMe }) {
            text = lastIncoming.bodyText
        } else if let last = threadStore.messages.last {
            text = last.bodyText
        } else {
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

    private func extractEmail(from addr: String?) -> String {
        guard let addr else { return "" }
        if let open = addr.firstIndex(of: "<"),
           let close = addr.firstIndex(of: ">") {
            return String(addr[addr.index(after: open)..<close])
        }
        return addr.trimmingCharacters(in: .whitespaces)
    }

    private func observeAccounts() async {
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

    // MARK: - Mutation helpers

    private func archiveSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        Task {
            do {
                try await composition.mailMutator.archive(threadId, accountId: accountId)
                showToast("Archived", undo: .unarchive(threadId: threadId, accountId: accountId))
            } catch {
                showToast("Archive failed", undo: nil)
            }
        }
    }

    private func starSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        Task {
            do {
                try await composition.mailMutator.star(threadId, accountId: accountId)
                showToast("Starred", undo: .unstar(threadId: threadId, accountId: accountId))
            } catch {
                showToast("Star failed", undo: nil)
            }
        }
    }

    private func trashThread(_ threadId: String, accountId: String) {
        Task {
            do {
                try await composition.mailMutator.trash(threadId, accountId: accountId)
                showToast("Trashed", undo: .untrash(threadId: threadId, accountId: accountId))
            } catch {
                showToast("Trash failed", undo: nil)
            }
        }
    }

    private func showToast(_ message: String, undo: ToastState.UndoAction?) {
        composition.toastMessage = ToastState(message: message, undoAction: undo)
        Task {
            try? await Task.sleep(for: .seconds(8))
            if composition.toastMessage?.message == message {
                composition.toastMessage = nil
            }
        }
    }

    private func handleUndo(_ action: ToastState.UndoAction) {
        composition.toastMessage = nil
        Task {
            switch action {
            case .unarchive(let threadId, let accountId):
                try? await composition.mailMutator.unarchive(threadId, accountId: accountId)
            case .unstar(let threadId, let accountId):
                try? await composition.mailMutator.unstar(threadId, accountId: accountId)
            case .untrash(let threadId, let accountId):
                try? await composition.mailMutator.untrash(threadId, accountId: accountId)
            }
        }
    }

    @ViewBuilder
    private func toastBar(_ toast: ToastState) -> some View {
        HStack(spacing: RBSpace.s2) {
            RBToast(toast.message, systemImage: "checkmark.circle.fill")
            if toast.undoAction != nil {
                Button("Undo") {
                    if let action = toast.undoAction {
                        handleUndo(action)
                    }
                }
                .buttonStyle(.rbGhost)
            }
        }
    }

    private func toggleTheme() {
        let raw = UserDefaults.standard.string(forKey: "rb-theme") ?? RBTheme.system.rawValue
        let current = RBTheme(rawValue: raw) ?? .system
        let next: RBTheme
        switch current {
        case .system: next = .dark
        case .dark: next = .light
        case .light: next = .system
        }
        UserDefaults.standard.set(next.rawValue, forKey: "rb-theme")
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
