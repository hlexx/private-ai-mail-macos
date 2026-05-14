import ActionsFeature
import BriefFeature
import ComposeFeature
import DesignSystem
import GRDB
import InboxFeature
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

            HStack(spacing: 0) {
                RBSidebar(
                    folders: sidebarFolders,
                    accounts: accounts.map { AccountRow(account: $0) },
                    activeFolder: $activeFolder
                )

                InboxView(store: inboxStore)
                    .frame(width: RBLayout.threadListWidth)

                ThreadView(
                    store: threadStore,
                    composer: {
                        if briefStore.brief != nil {
                            InlineComposer(
                                evidence: briefStore.brief?.evidence ?? [],
                                onEditInFull: { composition.showCompose = true },
                                onSend: { /* TODO(§15-step-7): wire real send */ }
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
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
