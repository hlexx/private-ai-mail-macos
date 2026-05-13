import DesignSystem
import SwiftUI

public struct ThreadView<ComposerContent: View>: View {
    let store: ThreadStore
    let composerContent: ComposerContent

    public init(store: ThreadStore, @ViewBuilder composer: () -> ComposerContent) {
        self.store = store
        self.composerContent = composer()
    }

    public var body: some View {
        Group {
            if store.messages.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    headSection
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            threadColumn
                            if store.hasAttachment {
                                attachmentBlock
                            }
                            composerContent
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    }
                }
                .background(Color.rbBgCanvas)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: RBSpace.s2) {
            Text("Re:")
                .font(.rbSerifItalic(48))
                .foregroundStyle(Color.rbFg3)
            Text(String(localized: "reading.empty.title", defaultValue: "Select a thread"))
                .rbTextStyle(.h3)
                .foregroundStyle(Color.rbFg1)
            Text(String(localized: "reading.empty.description", defaultValue: "Re:Box will brief you the moment you open it."))
                .rbTextStyle(.body)
                .foregroundStyle(Color.rbFg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgCanvas)
    }

    // MARK: - Head Section

    private var headSection: some View {
        VStack(alignment: .leading, spacing: RBSpace.s2) {
            Text(store.subject)
                .rbTextStyle(.h2)
                .foregroundStyle(Color.rbFg1)

            metaLine

            HStack(spacing: RBSpace.s2) {
                Spacer()
                Button { /* Archive stub */ } label: {
                    Label(String(localized: "thread.action.archive", defaultValue: "Archive"), systemImage: "archivebox")
                }
                .buttonStyle(.rbGhost)

                Button { /* Snooze stub */ } label: {
                    Label(String(localized: "thread.action.snooze", defaultValue: "Snooze"), systemImage: "clock")
                }
                .buttonStyle(.rbGhost)

                Button { /* Send-to stub */ } label: {
                    Label {
                        Text(String(localized: "thread.action.sendTo", defaultValue: "Send to \u{2197}"))
                    } icon: {
                        Image(systemName: "paperplane")
                    }
                }
                .buttonStyle(.rbGhost)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }

    private var metaLine: some View {
        HStack(spacing: RBSpace.s2) {
            Text(store.senderName)
                .foregroundStyle(Color.rbFg2)
            Text("\u{00B7}")
                .foregroundStyle(Color.rbFg3)
            Text(String(localized: "thread.meta.to \(store.accountEmail)", defaultValue: "to \(store.accountEmail)"))
                .foregroundStyle(Color.rbFg2)
            Text("\u{00B7}")
                .foregroundStyle(Color.rbFg3)
            Text(String(localized: "thread.meta.messages \(store.messageCount)", defaultValue: "\(store.messageCount) messages"))
                .foregroundStyle(Color.rbFg2)
            if store.hasAttachment {
                Text("\u{00B7}")
                    .foregroundStyle(Color.rbFg3)
                Text(String(localized: "thread.meta.attachments \(store.attachments.count)", defaultValue: "\(store.attachments.count) attachment\(store.attachments.count == 1 ? "" : "s")"))
                    .foregroundStyle(Color.rbFg2)
            }
        }
        .font(.rbMono(11))
    }

    // MARK: - Thread Column (Message Stack)

    private var threadColumn: some View {
        ForEach(store.messages) { message in
            MessageCardView(message: message)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Attachment Block

    private var attachmentBlock: some View {
        ForEach(store.attachments) { att in
            HStack(alignment: .center, spacing: 12) {
                // Thumbnail placeholder
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: RBRadius.xs)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.96, green: 0.95, blue: 0.9),
                                         Color(red: 0.84, green: 0.82, blue: 0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 38, height: 48)
                    Text(att.mime?.contains("pdf") == true ? "PDF" : "FILE")
                        .font(.rbMono(8, weight: .semibold))
                        .foregroundStyle(Color.rbGraphite900)
                        .padding(.leading, 4)
                        .padding(.bottom, 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(att.filename)
                        .font(.rbGeist(13, weight: .medium))
                        .foregroundStyle(Color.rbFg1)
                    Text(String(localized: "thread.attachment.meta \(att.formattedSize)", defaultValue: "\(att.formattedSize) \u{00B7} summarized locally"))
                        .font(.rbMono(11))
                        .foregroundStyle(Color.rbFg3)
                }

                Spacer()

                Button { /* Preview stub */ } label: {
                    Label(String(localized: "thread.attachment.preview", defaultValue: "Preview"), systemImage: "eye")
                }
                .buttonStyle(.rbGhost)

                Button { /* Summarize stub */ } label: {
                    Label(String(localized: "thread.attachment.summarize", defaultValue: "Summarize"), systemImage: "sparkle")
                }
                .buttonStyle(.rbSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.rbBgElev1)
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: RBRadius.md)
                    .strokeBorder(Color.rbStroke1, lineWidth: 1)
            )
            .padding(.top, 14)
        }
    }
}

extension ThreadView where ComposerContent == EmptyView {
    public init(store: ThreadStore) {
        self.store = store
        self.composerContent = EmptyView()
    }
}

// MARK: - Message Card

private struct MessageCardView: View {
    let message: MessageRow
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpace.s2) {
            HStack(alignment: .center, spacing: 10) {
                AvatarView(name: message.senderName, size: 28)
                Text(message.senderName)
                    .font(.rbGeist(13, weight: .semibold))
                    .foregroundStyle(Color.rbFg1)
                Spacer()
                Text(Self.timeFormatter.string(from: message.sentAt))
                    .font(.rbMono(11))
                    .foregroundStyle(Color.rbFg3)
            }
            Text(message.bodyText)
                .font(.rbGeist(14))
                .foregroundStyle(Color.rbFg2)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.md)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
    }
}
