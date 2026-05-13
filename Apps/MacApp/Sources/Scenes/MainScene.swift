import SwiftUI
import InboxFeature
import ThreadFeature
import BriefFeature
import DesignSystem
import Persistence
import GRDB

struct MainScene: View {

    let composition: CompositionRoot

    @State private var sidebarSelection: AccountFolderID? = .inbox
    @State private var accounts: [AccountRecord] = []

    private var inboxStore: InboxStore { composition.inboxStore }
    private var threadStore: ThreadStore { composition.threadStore }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            InboxView(store: inboxStore)
        } detail: {
            ThreadView(store: threadStore)
        }
        .navigationTitle(String(localized: "app.title", defaultValue: "Private AI Mail"))
        .onChange(of: inboxStore.selectedThreadID) { _, newValue in
            if let threadId = newValue,
               let thread = inboxStore.threads.first(where: { $0.id == threadId }) {
                threadStore.observe(threadId: threadId, accountId: thread.accountId)
            } else {
                threadStore.stopObserving()
            }
        }
        .task {
            observeAccounts()
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

    private func observeAccounts() {
        Task {
            let observation = ValueObservation.tracking { db in
                try AccountRecord.fetchAll(db)
            }
            do {
                for try await records in observation.values(in: composition.db.dbQueue) {
                    self.accounts = records
                }
            } catch {
                // Observation ended
            }
        }
    }

}

// MARK: - Local identifiers

enum AccountFolderID: Hashable {
    case inbox, starred, sent
    case account(String, String)
}
