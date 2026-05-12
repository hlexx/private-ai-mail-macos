import SwiftUI
import InboxFeature
import ThreadFeature
import BriefFeature
import DesignSystem

struct MainScene: View {

    let composition: CompositionRoot

    @State private var sidebarSelection: AccountFolderID? = .inbox
    @State private var threadSelection: ThreadID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            threadList
        } detail: {
            reading
        }
        .navigationTitle(String(localized: "app.title", defaultValue: "Private AI Mail"))
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
                Text(String(localized: "sidebar.no_accounts", defaultValue: "No accounts connected"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }

    private var threadList: some View {
        VStack {
            ContentUnavailableView(
                String(localized: "threads.empty.title", defaultValue: "No threads yet"),
                systemImage: "envelope.open",
                description: Text(String(
                    localized: "threads.empty.description",
                    defaultValue: "Connect a Gmail or Microsoft 365 account to get started."
                ))
            )
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 600)
    }

    private var reading: some View {
        VStack {
            ContentUnavailableView(
                String(localized: "reading.empty.title", defaultValue: "Select a thread"),
                systemImage: "text.alignleft",
                description: Text(String(
                    localized: "reading.empty.description",
                    defaultValue: "Pick a conversation to see the AI brief and reply options."
                ))
            )
        }
    }
}

// MARK: - Local stub identifiers

enum AccountFolderID: Hashable {
    case inbox, starred, sent
    case account(UUID, String)
}

struct ThreadID: Hashable {
    let raw: String
}
