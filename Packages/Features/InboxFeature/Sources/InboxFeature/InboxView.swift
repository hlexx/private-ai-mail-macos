import SwiftUI

public struct InboxView: View {
    @Bindable var store: InboxStore

    public init(store: InboxStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.threads.isEmpty {
                ContentUnavailableView(
                    String(localized: "threads.empty.title", defaultValue: "No threads yet"),
                    systemImage: "envelope.open",
                    description: Text(String(
                        localized: "threads.empty.description",
                        defaultValue: "Connect a Gmail account to get started."
                    ))
                )
            } else {
                List(store.threads, selection: $store.selectedThreadID) { thread in
                    ThreadRowView(thread: thread)
                        .tag(thread.id)
                }
                .listStyle(.inset)
            }
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 600)
        .task {
            store.startObserving()
        }
    }
}

private struct ThreadRowView: View {
    let thread: ThreadRow
    private static let dateFormatter = RelativeDateTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(thread.subject)
                    .font(.headline)
                    .fontWeight(thread.hasUnread ? .bold : .regular)
                    .lineLimit(1)
                Spacer()
                Text(Self.dateFormatter.localizedString(for: thread.lastMessageAt, relativeTo: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(thread.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if thread.messageCount > 1 {
                    Text("\(thread.messageCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
