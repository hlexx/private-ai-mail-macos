import BriefFeature
import DesignSystem
import GRDB
import InboxFeature
import Persistence
import SwiftUI
import ThreadFeature

struct MainScene: View {

    let composition: CompositionRoot

    @State private var sidebarSelection: AccountFolderID? = .inbox
    @State private var accounts: [AccountRecord] = []
    @Environment(\.openSettings) private var openSettings

    private var inboxStore: InboxStore { composition.inboxStore }
    private var threadStore: ThreadStore { composition.threadStore }

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

            NavigationSplitView {
                sidebar
            } content: {
                InboxView(store: inboxStore)
            } detail: {
                ThreadView(store: threadStore)
            }
        }
        .background(Color.rbBgDeep)
        .overlay {
            if composition.showActionSheet {
                // Task 11 will fill in the ActionSheetView
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { composition.showActionSheet = false }
            }
        }
        .onChange(of: inboxStore.selectedThreadID) { _, newValue in
            if let threadId = newValue,
               let thread = inboxStore.threads.first(where: { $0.id == threadId }) {
                threadStore.observe(threadId: threadId, accountId: thread.accountId)
            } else {
                threadStore.stopObserving()
            }
        }
        .task {
            await observeAccounts()
        }
        .keyboardShortcut(key: "k", modifiers: .command) {
            composition.showActionSheet.toggle()
        }
    }

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section(String(localized: "sidebar.section.unified", defaultValue: "Unified")) {
                Label(String(localized: "sidebar.inbox", defaultValue: "Inbox"), systemImage: "tray")
                    .tag(AccountFolderID.inbox)
                Label(String(localized: "sidebar.starred", defaultValue: "Starred"), systemImage: "star")
                    .tag(AccountFolderID.starred)
                Label(String(localized: "sidebar.sent", defaultValue: "Sent"), systemImage: "paperplane")
                    .tag(AccountFolderID.sent)
            }
            Section(String(localized: "sidebar.section.accounts", defaultValue: "Accounts")) {
                if accounts.isEmpty {
                    Text(String(localized: "sidebar.no_accounts", defaultValue: "No accounts connected"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(accounts, id: \.id) { account in
                        Label(account.email, systemImage: "person.crop.circle")
                            .tag(AccountFolderID.account(account.id, account.email))
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
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

// MARK: - Local identifiers

enum AccountFolderID: Hashable {
    case inbox, starred, sent
    case account(String, String)
}

// MARK: - Keyboard shortcut helper

private extension View {
    func keyboardShortcut(key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut(key, modifiers: modifiers)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }
}
