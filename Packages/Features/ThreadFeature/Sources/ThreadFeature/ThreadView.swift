import SwiftUI

public struct ThreadView: View {
    let store: ThreadStore

    public init(store: ThreadStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.messages.isEmpty {
                ContentUnavailableView(
                    String(localized: "reading.empty.title", defaultValue: "Select a thread"),
                    systemImage: "text.alignleft",
                    description: Text(String(
                        localized: "reading.empty.description",
                        defaultValue: "Pick a conversation to see its messages."
                    ))
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(store.messages) { message in
                            MessageView(message: message)
                            if message.id != store.messages.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

private struct MessageView: View {
    let message: MessageRow
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.fromAddr)
                    .font(.headline)
                Spacer()
                Text(Self.dateFormatter.string(from: message.sentAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.bodyText)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
