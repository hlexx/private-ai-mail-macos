import DesignSystem
import SwiftUI

public struct InboxView: View {
    @Bindable var store: InboxStore
    var onArchive: ((String, String) -> Void)?
    var onTrash: ((String, String) -> Void)?

    public init(
        store: InboxStore,
        onArchive: ((String, String) -> Void)? = nil,
        onTrash: ((String, String) -> Void)? = nil
    ) {
        self.store = store
        self.onArchive = onArchive
        self.onTrash = onTrash
    }

    public var body: some View {
        VStack(spacing: 0) {
            threadListHeader
            filterChipsRow
            threadList

            // Trailing flexible spacer keeps the header pinned directly
            // under the toolbar when the threadList is in its empty state
            // (`ContentUnavailableView` is not greedy on macOS 26 / Swift 6).
            // When real threads land the `List` is naturally greedy so the
            // spacer collapses to zero. Matches `.rb-list` / `.rb-list-header`
            // in design/re-box/project/app/app.css.
            Spacer(minLength: 0)
        }
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
            case .archive: return String(localized: "inbox.header.archive", defaultValue: "Archive")
            }
        case .account:
            return String(localized: "inbox.header.account", defaultValue: "Account")
        }
    }

    private var threadListHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(headerTitle)
                .font(.rbGeist(18, weight: .semibold))
                .foregroundStyle(Color.rbFg1)
            Spacer()
            Text("\(store.filteredThreads.count) threads")
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

    // MARK: - Thread List

    private var threadList: some View {
        Group {
            if store.filteredThreads.isEmpty {
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
                    ThreadRowView(
                        thread: thread,
                        isActive: thread.id == store.selectedThreadID
                    )
                    .tag(thread.id)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading) {
                        if let onArchive {
                            Button {
                                onArchive(thread.id, thread.accountId)
                            } label: {
                                Label(String(localized: "inbox.swipe.archive", defaultValue: "Archive"), systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if let onTrash {
                            Button(role: .destructive) {
                                onTrash(thread.id, thread.accountId)
                            } label: {
                                Label(String(localized: "inbox.swipe.trash", defaultValue: "Trash"), systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - Thread Row

private struct ThreadRowView: View {
    let thread: ThreadRow
    let isActive: Bool

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(name: thread.senderName, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                fromLine
                subjectLine
                previewLine
                chipsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(Self.timeFormatter.localizedString(for: thread.lastMessageAt, relativeTo: .now))
                    .font(.rbMono(10.5))
                    .foregroundStyle(Color.rbFg3)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, RBSpace.s4)
        .padding(.vertical, 12)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.rbCitron500)
                    .frame(width: 3)
                    .padding(.vertical, 12)
            }
        }
        .overlay(alignment: .bottom) {
            Color.rbStroke1.frame(height: 1)
        }
    }

    private var fromLine: some View {
        HStack(spacing: 0) {
            if thread.hasUnread {
                Circle()
                    .fill(Color.rbCitron500)
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 6)
            }
            Text(thread.senderName)
                .font(.rbGeist(13, weight: .semibold))
                .foregroundStyle(Color.rbFg1)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Self.extractDomain(from: thread.senderAddr))
                .font(.rbMono(10.5))
                .foregroundStyle(Color.rbFg3)
                .lineLimit(1)
        }
    }

    private var subjectLine: some View {
        Text(thread.subject)
            .font(.rbGeist(13, weight: .medium))
            .foregroundStyle(Color.rbFg1)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var previewLine: some View {
        Text(thread.snippet)
            .font(.rbGeist(12.5))
            .foregroundStyle(Color.rbFg3)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var chipsRow: some View {
        let chips = deriveChips()
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    SignalChip(kind: chip)
                }
            }
            .padding(.top, 4)
        }
    }

    private func deriveChips() -> [SignalChip.Kind] {
        var chips: [SignalChip.Kind] = []
        // TODO(§15-step-4): drive chips from AIKit brief
        if thread.attachmentCount > 0 {
            chips.append(.att(pages: nil))
        }
        if thread.messageCount > 1 {
            // Show message count as a subtle indicator
        }
        return chips
    }

    private static func extractDomain(from addr: String) -> String {
        let bare: String
        if let lt = addr.firstIndex(of: "<"), let gt = addr.firstIndex(of: ">"), lt < gt {
            bare = String(addr[addr.index(after: lt)..<gt])
        } else {
            bare = addr
        }
        return bare.split(separator: "@").last.map(String.init) ?? ""
    }

    private var rowBackground: Color {
        if isActive {
            return Color.rbCitron500.opacity(0.09)
        } else if thread.hasUnread {
            return Color.rbGraphite50.opacity(0.02)
        } else {
            return Color.clear
        }
    }
}
