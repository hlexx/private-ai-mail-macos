import ActionsFeature
import DesignSystem
import SwiftUI

public struct InboxView: View {
    @Bindable var store: InboxStore
    let actionStore: TrustActionUIStore?
    var onArchive: ((String, String) -> Void)?
    var onTrash: ((String, String) -> Void)?

    public init(
        store: InboxStore,
        actionStore: TrustActionUIStore? = nil,
        onArchive: ((String, String) -> Void)? = nil,
        onTrash: ((String, String) -> Void)? = nil
    ) {
        self.store = store
        self.actionStore = actionStore
        self.onArchive = onArchive
        self.onTrash = onTrash
    }

    public var body: some View {
        VStack(spacing: 0) {
            threadListHeader
            filterChipsRow
            searchWarningBanner
            actionOutboxStrip
            threadList

            // Trailing flexible spacer keeps the header pinned directly
            // under the toolbar when the threadList is in its empty state
            // (`ContentUnavailableView` is not greedy on macOS 26 / Swift 6).
            // When real threads land the `List` is naturally greedy so the
            // spacer collapses to zero. Matches `.rb-list` / `.rb-list-header`
            // in design/re-box/project/app/app.css.
            Spacer(minLength: 0)
        }
        .trustActionApprovalAlert(actionStore)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.rbBgCanvas)
        .onAppear {
            store.startObserving()
        }
        .onDisappear {
            store.stopObserving()
        }
    }

    // MARK: - Header

    private var headerTitle: String {
        switch store.selection {
        case .folder(let fid):
            switch fid {
            case .inbox: return String(localized: "inbox.header.title", defaultValue: "Inbox")
            case .needsReply: return String(localized: "inbox.header.needsReply", defaultValue: "Needs reply")
            case .hasDeadline: return String(localized: "inbox.header.hasDeadline", defaultValue: "Has deadline")
            case .attachments: return String(localized: "inbox.header.attachments", defaultValue: "Attachments")
            case .logged: return String(localized: "inbox.header.logged", defaultValue: "Logged")
            case .starred: return String(localized: "inbox.header.starred", defaultValue: "Starred")
            case .sent: return String(localized: "inbox.header.sent", defaultValue: "Sent")
            case .trash: return String(localized: "inbox.header.trash", defaultValue: "Trash")
            case .spam: return String(localized: "inbox.header.spam", defaultValue: "Spam")
            case .archive: return String(localized: "inbox.header.archive", defaultValue: "Archive")
            }
        case .account:
            return String(localized: "inbox.header.account", defaultValue: "Account")
        case .allAccountsAllFolders:
            return String(localized: "inbox.header.allAccounts", defaultValue: "All Accounts")
        }
    }

    private var threadListHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(headerTitle)
                .font(.rbGeist(18, weight: .semibold))
                .foregroundStyle(Color.rbFg1)
            Spacer()
            Text(headerCountText)
                .font(.rbMono(11))
                .foregroundStyle(Color.rbFg3)
        }
        .padding(.horizontal, RBSpace.s4)
        .padding(.top, 14)
        .padding(.bottom, RBSpace.s2)
        .overlay(alignment: .bottom) {
            Color.rbStroke1.frame(height: 1)
        }
    }

    private var headerCountText: String {
        if store.activeSearchText != nil {
            return "\(store.filteredThreads.count) results"
        }
        return "\(store.filteredThreads.count) threads"
    }

    // MARK: - Filter Chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ThreadFilter.allCases, id: \.self) { f in
                    RBFilterChip(
                        label: f.label,
                        isOn: store.filter == f
                    ) {
                        store.filter = f
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, RBSpace.s2)
        }
        .overlay(alignment: .bottom) {
            Color.rbStroke1.frame(height: 1)
        }
    }

    @ViewBuilder
    private var searchWarningBanner: some View {
        if let warning = store.searchWarningText {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(warning)
                    .font(.rbGeist(12))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.rbToneCoral600)
            .padding(.horizontal, RBSpace.s4)
            .padding(.vertical, 8)
            .background(Color.rbToneCoral600.opacity(0.08))
            .overlay(alignment: .bottom) {
                Color.rbStroke1.frame(height: 1)
            }
        }
    }

    // MARK: - Thread List

    private var threadList: some View {
        Group {
            if case .loading = store.searchState {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(String(localized: "threads.search.loading", defaultValue: "Searching"))
                        .font(.rbGeist(13, weight: .medium))
                        .foregroundStyle(Color.rbFg2)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if store.searchState == .disabled && store.activeSearchText != nil {
                ContentUnavailableView(
                    String(localized: "threads.search.disabled.title", defaultValue: "Search unavailable"),
                    systemImage: "magnifyingglass",
                    description: Text(String(
                        localized: "threads.search.disabled.description",
                        defaultValue: "Local search is not available in this build."
                    ))
                )
            } else if case .failed(_, _, let message) = store.searchState {
                ContentUnavailableView(
                    String(localized: "threads.search.failed.title", defaultValue: "Search failed"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            } else if case .empty = store.searchState {
                ContentUnavailableView(
                    String(localized: "threads.search.empty.title", defaultValue: "No search results"),
                    systemImage: "magnifyingglass",
                    description: Text(String(
                        localized: "threads.search.empty.description",
                        defaultValue: "No indexed threads match this search."
                    ))
                )
            } else if store.filteredThreads.isEmpty {
                if store.filter != .all && !store.threads.isEmpty {
                    ContentUnavailableView(
                        String(localized: "threads.filter.empty.title", defaultValue: "No matching threads"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(String(
                            localized: "threads.filter.empty.description",
                            defaultValue: "No threads match the selected filter."
                        ))
                    )
                } else {
                    ContentUnavailableView(
                        String(localized: "threads.empty.title", defaultValue: "No threads yet"),
                        systemImage: "envelope.open",
                        description: Text(String(
                            localized: "threads.empty.description",
                            defaultValue: "Connect a Gmail account to get started."
                        ))
                    )
                }
            } else {
                List(store.filteredThreads, selection: $store.selectedThreadID) { thread in
                    InboxThreadRowView(
                        thread: thread,
                        isActive: thread.id == store.selectedThreadID
                    )
                    .tag(thread.id)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading) {
                        if actionStore != nil {
                            Button {
                                Task {
                                    await requestAction(.archiveThread, for: thread)
                                }
                            } label: {
                                Label(String(localized: "inbox.swipe.archive", defaultValue: "Archive"), systemImage: "archivebox")
                            }
                            .tint(.orange)
                        } else if let onArchive {
                            Button {
                                onArchive(thread.id, thread.accountId)
                            } label: {
                                Label(String(localized: "inbox.swipe.archive", defaultValue: "Archive"), systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if actionStore != nil {
                            Button(role: .destructive) {
                                Task {
                                    await requestAction(.trashThread, for: thread)
                                }
                            } label: {
                                Label(String(localized: "inbox.swipe.trash", defaultValue: "Trash"), systemImage: "trash")
                            }
                        } else if let onTrash {
                            Button(role: .destructive) {
                                onTrash(thread.id, thread.accountId)
                            } label: {
                                Label(String(localized: "inbox.swipe.trash", defaultValue: "Trash"), systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            Task { await requestAction(.draftReply, for: thread) }
                        } label: {
                            Label(String(localized: "inbox.action.draftReply", defaultValue: "Draft reply"), systemImage: "arrowshape.turn.up.left")
                        }
                        Button {
                            Task { await requestAction(.starThread, for: thread) }
                        } label: {
                            Label(String(localized: "inbox.action.star", defaultValue: "Star"), systemImage: "star")
                        }
                        Button {
                            Task { await requestAction(.markRead, for: thread) }
                        } label: {
                            Label(String(localized: "inbox.action.markRead", defaultValue: "Mark read"), systemImage: "envelope.open")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { await requestAction(.trashThread, for: thread) }
                        } label: {
                            Label(String(localized: "inbox.action.trash", defaultValue: "Trash"), systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

}
