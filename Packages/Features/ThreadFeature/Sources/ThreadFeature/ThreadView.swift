import DesignSystem
import SwiftUI

public enum ThreadViewAnchor: Hashable {
    case head
    case composer
}

public struct ThreadView<ComposerContent: View, BriefContent: View, TranslationHeader: View>: View {
    let store: ThreadStore
    let composerContent: ComposerContent
    let briefContent: BriefContent
    let translationHeader: TranslationHeader
    var onArchive: (() -> Void)?
    var onStar: (() -> Void)?
    var showTranslated: Bool
    var translatedTexts: [String: String]
    var translatedNodes: [String: [String: String]]
    var onTextNodesExtracted: ((String, [TranslationTextNode]) -> Void)?
    var onScrollProxy: ((ScrollViewProxy) -> Void)?

    public init(
        store: ThreadStore,
        onArchive: (() -> Void)? = nil,
        onStar: (() -> Void)? = nil,
        showTranslated: Bool = false,
        translatedTexts: [String: String] = [:],
        translatedNodes: [String: [String: String]] = [:],
        onTextNodesExtracted: ((String, [TranslationTextNode]) -> Void)? = nil,
        onScrollProxy: ((ScrollViewProxy) -> Void)? = nil,
        @ViewBuilder composer: () -> ComposerContent,
        @ViewBuilder briefRail: () -> BriefContent = { EmptyView() },
        @ViewBuilder translationHeader: () -> TranslationHeader = { EmptyView() }
    ) {
        self.store = store
        self.onArchive = onArchive
        self.onStar = onStar
        self.showTranslated = showTranslated
        self.translatedTexts = translatedTexts
        self.translatedNodes = translatedNodes
        self.onTextNodesExtracted = onTextNodesExtracted
        self.onScrollProxy = onScrollProxy
        self.composerContent = composer()
        self.briefContent = briefRail()
        self.translationHeader = translationHeader()
    }

    public var body: some View {
        Group {
            if store.messages.isEmpty {
                emptyState
            } else {
                // Mirrors `.rb-read` from design/re-box/project/app/app.css:
                //   grid-template-rows: auto 1fr auto
                //   head spans the whole pane; body splits 1fr / 340px.
                VStack(spacing: 0) {
                    headSection
                    translationHeader
                    HStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    threadColumn
                                    if store.hasAttachment {
                                        attachmentBlock
                                    }
                                    composerContent
                                        .id(ThreadViewAnchor.composer)
                                }
                                .padding(.horizontal, 28)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                            }
                            .onAppear { onScrollProxy?(proxy) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Brief rail sits beside the thread column, under the
                        // shared head. The rail enforces its own width via
                        // RBLayout.briefRailWidth at the caller site.
                        briefContent
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
                Button { onArchive?() } label: {
                    Label(String(localized: "thread.action.archive", defaultValue: "Archive"), systemImage: "archivebox")
                }
                .buttonStyle(.rbGhost)
                .disabled(onArchive == nil)

                Button { onStar?() } label: {
                    Label(
                        store.isStarred
                            ? String(localized: "thread.action.unstar", defaultValue: "Unstar")
                            : String(localized: "thread.action.star", defaultValue: "Star"),
                        systemImage: store.isStarred ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.rbGhost)
                .disabled(onStar == nil)

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
            Text("to \(store.accountEmail)")
                .foregroundStyle(Color.rbFg2)
            Text("\u{00B7}")
                .foregroundStyle(Color.rbFg3)
            Text("\(store.messageCount) messages")
                .foregroundStyle(Color.rbFg2)
            if store.hasAttachment {
                Text("\u{00B7}")
                    .foregroundStyle(Color.rbFg3)
                Text("\(store.attachments.count) attachment\(store.attachments.count == 1 ? "" : "s")")
                    .foregroundStyle(Color.rbFg2)
            }
        }
        .font(.rbMono(11))
    }

    // MARK: - Thread Column (Message Stack)

    private var threadColumn: some View {
        ForEach(store.messages) { message in
            MessageCardView(
                message: message,
                showTranslated: showTranslated,
                translatedText: showTranslated ? translatedTexts[message.id] : nil,
                translatedNodes: showTranslated ? translatedNodes[message.id] : nil,
                onTextNodesExtracted: onTextNodesExtracted.map { callback in
                    { nodes in callback(message.id, nodes) }
                }
            )
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
                    Text("\(att.formattedSize) \u{00B7} summarized locally")
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

extension ThreadView where ComposerContent == EmptyView, BriefContent == EmptyView, TranslationHeader == EmptyView {
    public init(store: ThreadStore, onArchive: (() -> Void)? = nil, onStar: (() -> Void)? = nil) {
        self.store = store
        self.onArchive = onArchive
        self.onStar = onStar
        self.showTranslated = false
        self.translatedTexts = [:]
        self.translatedNodes = [:]
        self.onTextNodesExtracted = nil
        self.onScrollProxy = nil
        self.composerContent = EmptyView()
        self.briefContent = EmptyView()
        self.translationHeader = EmptyView()
    }
}

// MARK: - Message Card

private struct MessageCardView: View {
    let message: MessageRow
    let showTranslated: Bool
    let translatedText: String?
    let translatedNodes: [String: String]?
    var onTextNodesExtracted: (([TranslationTextNode]) -> Void)?
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    init(
        message: MessageRow,
        showTranslated: Bool = false,
        translatedText: String? = nil,
        translatedNodes: [String: String]? = nil,
        onTextNodesExtracted: (([TranslationTextNode]) -> Void)? = nil
    ) {
        self.message = message
        self.showTranslated = showTranslated
        self.translatedText = translatedText
        self.translatedNodes = translatedNodes
        self.onTextNodesExtracted = onTextNodesExtracted
    }

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
            // When showing translated for HTML messages, render via HTMLWebView
            // with translatedNodes injected (preserves layout).
            // For plain-text-only messages, fall back to Text(translated).
            if showTranslated, message.bodyHtml != nil, translatedNodes != nil || onTextNodesExtracted != nil {
                MessageBodyView(
                    bodyHtml: message.bodyHtml,
                    bodyText: message.bodyText,
                    snippet: message.snippet,
                    attachments: message.inlineAttachments.map { att in
                        HTMLWebView.AttachmentData(
                            contentId: att.contentId,
                            mime: att.mime,
                            data: Data(base64Encoded: att.dataBase64, options: .ignoreUnknownCharacters) ?? Data()
                        )
                    },
                    translatedNodes: translatedNodes,
                    onTextNodesExtracted: onTextNodesExtracted
                )
            } else if let translated = translatedText, message.bodyHtml == nil {
                Text(translated)
                    .font(.rbGeist(14))
                    .foregroundStyle(Color.rbFg2)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            } else {
                MessageBodyView(
                    bodyHtml: message.bodyHtml,
                    bodyText: message.bodyText,
                    snippet: message.snippet,
                    attachments: message.inlineAttachments.map { att in
                        HTMLWebView.AttachmentData(
                            contentId: att.contentId,
                            mime: att.mime,
                            data: Data(base64Encoded: att.dataBase64, options: .ignoreUnknownCharacters) ?? Data()
                        )
                    }
                )
            }
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
