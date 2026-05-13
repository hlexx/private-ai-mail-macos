import SwiftUI
import DesignSystem

public struct InboxView: View {
    @Bindable var store: InboxStore

    public init(store: InboxStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            threadListHeader
            filterChipsRow
            threadList
        }
        .background(Color.rbBgCanvas)
        .task {
            store.startObserving()
        }
        .onDisappear {
            store.stopObserving()
        }
    }

    // MARK: - Header

    private var threadListHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Inbox")
                .font(.rbGeist(18, weight: .semibold))
                .foregroundStyle(Color.rbFg1)
            Spacer()
            Text("\(store.filteredThreads.count) threads · \(store.needsReplyCount) need reply")
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
                ContentUnavailableView(
                    String(localized: "threads.empty.title", defaultValue: "No threads yet"),
                    systemImage: "envelope.open",
                    description: Text(String(
                        localized: "threads.empty.description",
                        defaultValue: "Connect a Gmail account to get started."
                    ))
                )
            } else {
                ScrollViewReader { proxy in
                    List(store.filteredThreads, selection: $store.selectedThreadID) { thread in
                        ThreadRowView(
                            thread: thread,
                            isActive: thread.id == store.selectedThreadID
                        )
                        .tag(thread.id)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
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
            Text(thread.senderAddr.contains("@") ? String(thread.senderAddr.split(separator: "@").last ?? "") : "")
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
