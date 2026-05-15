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

struct MainScene: View {

    let composition: CompositionRoot

    @State private var activeFolder: String = "inbox"
    @State private var accounts: [AccountRecord] = []
    @Environment(\.openSettings) private var openSettings

    private var inboxStore: InboxStore { composition.inboxStore }
    private var threadStore: ThreadStore { composition.threadStore }
    private var briefStore: BriefStore { composition.briefStore }

    var body: some View {
        VStack(spacing: 0) {
            RBToolbar(
                accounts: accounts,
                activeAccountID: composition.activeAccountID,
                onCycleAccount: { composition.cycleActiveAccount(accounts: accounts) },
                onToggleTheme: { toggleTheme() },
                onOpenSettings: { openSettings() },
                onCompose: { composition.showCompose = true },
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
                    activeFolder: $activeFolder
                )
                .frame(
                    minWidth: 180,
                    idealWidth: RBLayout.sidebarWidth,
                    maxWidth: 360,
                    maxHeight: .infinity,
                    alignment: .top
                )

                InboxView(store: inboxStore)
                    .frame(
                        minWidth: 280,
                        idealWidth: RBLayout.threadListWidth,
                        maxWidth: 480,
                        maxHeight: .infinity,
                        alignment: .top
                    )

                ThreadView(
                    store: threadStore,
                    composer: {
                        if briefStore.brief != nil {
                            InlineComposer(
                                evidence: briefStore.brief?.evidence ?? [],
                                onEditInFull: {
                                    prefillComposeForReply()
                                    composition.showCompose = true
                                },
                                onSend: { bodyText in
                                    sendInlineReply(bodyText: bodyText)
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
        .onChange(of: activeFolder) { _, newFolder in
            inboxStore.activeFolder = newFolder
        }
        .onChange(of: inboxStore.selectedThreadID) { _, newValue in
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
    }

    private var sidebarFolders: [FolderItem] {
        var folders = FolderItem.defaultFolders
        let unreadCount = inboxStore.threads.filter(\.hasUnread).count
        if let idx = folders.firstIndex(where: { $0.id == "inbox" }) {
            folders[idx].count = unreadCount > 0 ? unreadCount : nil
        }
        return folders
    }

    // MARK: - Reply Helpers

    private func prefillComposeForReply() {
        let vm = composition.composeViewModel
        guard let lastMessage = threadStore.messages.last else { return }
        vm.prefillReply(
            fromAddr: lastMessage.fromAddr,
            subject: threadStore.subject,
            threadID: lastMessage.threadId,
            lastMessageID: lastMessage.id
        )
        vm.accounts = accounts.map { AccountInfo(id: $0.id, email: $0.email, displayName: $0.displayName) }
        if let activeID = composition.activeAccountID {
            vm.selectedAccountID = activeID
            vm.selectedAccountEmail = accounts.first(where: { $0.id == activeID })?.email
        }
    }

    private func sendInlineReply(bodyText: String) {
        guard let accountID = composition.activeAccountID,
              let account = accounts.first(where: { $0.id == accountID }),
              let lastMessage = threadStore.messages.last else { return }

        let replySubject = ComposeViewModel.deduplicateRePrefix(threadStore.subject)

        let draft = ComposeDraft(
            accountID: accountID,
            from: Address(name: nil, email: account.email),
            to: [Address(name: nil, email: extractEmail(from: lastMessage.fromAddr))],
            subject: replySubject,
            body: bodyText,
            replyContext: ReplyContext(
                threadID: lastMessage.threadId,
                inReplyToMessageID: lastMessage.id
            )
        )

        let service = composition.makeComposeService(accountId: accountID)
        Task {
            do {
                _ = try await service.send(draft)
            } catch {
                // Error handling deferred to compose UI
            }
        }
    }

    private func extractEmail(from addr: String) -> String {
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
