import ActionsFeature
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
    var onMarkRead: (() -> Void)?
    var onTrash: (() -> Void)?
    let actionStore: TrustActionUIStore?
    var showTranslated: Bool
    var translatedTexts: [String: String]
    var translatedNodes: [String: [String: String]]
    var onTextNodesExtracted: ((String, [TranslationTextNode]) -> Void)?
    var onScrollProxy: ((ScrollViewProxy) -> Void)?
    var attachmentSummaryStore: AttachmentSummaryStore?
    var attachmentUIStateProvider: (AttachmentInfo) -> AttachmentUIState

    public init(
        store: ThreadStore,
        actionStore: TrustActionUIStore? = nil,
        onArchive: (() -> Void)? = nil,
        onStar: (() -> Void)? = nil,
        onMarkRead: (() -> Void)? = nil,
        onTrash: (() -> Void)? = nil,
        showTranslated: Bool = false,
        translatedTexts: [String: String] = [:],
        translatedNodes: [String: [String: String]] = [:],
        onTextNodesExtracted: ((String, [TranslationTextNode]) -> Void)? = nil,
        onScrollProxy: ((ScrollViewProxy) -> Void)? = nil,
        attachmentSummaryStore: AttachmentSummaryStore? = nil,
        attachmentUIStateProvider: ((AttachmentInfo) -> AttachmentUIState)? = nil,
        @ViewBuilder composer: () -> ComposerContent,
        @ViewBuilder briefRail: () -> BriefContent = { EmptyView() },
        @ViewBuilder translationHeader: () -> TranslationHeader = { EmptyView() }
    ) {
        self.store = store
        self.actionStore = actionStore
        self.onArchive = onArchive
        self.onStar = onStar
        self.onMarkRead = onMarkRead
        self.onTrash = onTrash
        self.showTranslated = showTranslated
        self.translatedTexts = translatedTexts
        self.translatedNodes = translatedNodes
        self.onTextNodesExtracted = onTextNodesExtracted
        self.onScrollProxy = onScrollProxy
        self.attachmentSummaryStore = attachmentSummaryStore
        let resolver = AttachmentUIStateResolver()
        self.attachmentUIStateProvider = attachmentUIStateProvider ?? { resolver.state(for: $0) }
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
                    actionOutboxStrip
                    translationHeader
                    HStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            VStack(spacing: 0) {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 0) {
                                        threadColumn
                                        if store.hasAttachment {
                                            attachmentBlock
                                        }
                                    }
                                    .padding(.horizontal, 28)
                                    .padding(.top, 20)
                                    .padding(.bottom, 24)
                                }
                                .onAppear { onScrollProxy?(proxy) }

                                composerContent
                                    .id(ThreadViewAnchor.composer)
                                    .padding(.horizontal, 28)
                                    .padding(.bottom, 24)
                                    .background(Color.rbBgCanvas)
                            }
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
        .trustActionApprovalAlert(actionStore)
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
                Button { requestActionOrFallback(.draftReply, fallback: nil) } label: {
                    Label(String(localized: "thread.action.draftReply", defaultValue: "Draft"), systemImage: "arrowshape.turn.up.left")
                }
                .buttonStyle(.rbGhost)
                .disabled(actionTarget == nil)

                Button { requestActionOrFallback(.archiveThread, fallback: onArchive) } label: {
                    Label(String(localized: "thread.action.archive", defaultValue: "Archive"), systemImage: "archivebox")
                }
                .buttonStyle(.rbGhost)
                .disabled(actionStore == nil && onArchive == nil)

                Button { requestActionOrFallback(.starThread, fallback: onStar) } label: {
                    Label(
                        store.isStarred
                            ? String(localized: "thread.action.unstar", defaultValue: "Unstar")
                            : String(localized: "thread.action.star", defaultValue: "Star"),
                        systemImage: store.isStarred ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.rbGhost)
                .disabled(actionStore == nil && onStar == nil)

                Button { requestActionOrFallback(.markRead, fallback: onMarkRead) } label: {
                    Label(String(localized: "thread.action.markRead", defaultValue: "Mark read"), systemImage: "envelope.open")
                }
                .buttonStyle(.rbGhost)
                .disabled(actionStore == nil && onMarkRead == nil)

                Button(role: .destructive) { requestActionOrFallback(.trashThread, fallback: onTrash) } label: {
                    Label(String(localized: "thread.action.trash", defaultValue: "Trash"), systemImage: "trash")
                }
                .buttonStyle(.rbGhost)
                .disabled(actionStore == nil && onTrash == nil)

                Button {} label: {
                    Label(String(localized: "thread.action.snooze", defaultValue: "Snooze"), systemImage: "clock")
                }
                .buttonStyle(.rbGhost)
                .disabled(true)
                .help(String(localized: "thread.action.snooze.help", defaultValue: "Not available yet"))

                Button {} label: {
                    Label {
                        Text(String(localized: "thread.action.sendTo", defaultValue: "Send to"))
                    } icon: {
                        Image(systemName: "paperplane")
                    }
                }
                .buttonStyle(.rbGhost)
                .disabled(true)
                .help(String(localized: "thread.action.sendTo.help", defaultValue: "Not available yet"))
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
            .id(message.id)
            .padding(.bottom, 12)
        }
    }
}

extension ThreadView where ComposerContent == EmptyView, BriefContent == EmptyView, TranslationHeader == EmptyView {
    public init(
        store: ThreadStore,
        actionStore: TrustActionUIStore? = nil,
        onArchive: (() -> Void)? = nil,
        onStar: (() -> Void)? = nil,
        onMarkRead: (() -> Void)? = nil,
        onTrash: (() -> Void)? = nil
    ) {
        self.store = store
        self.actionStore = actionStore
        self.onArchive = onArchive
        self.onStar = onStar
        self.onMarkRead = onMarkRead
        self.onTrash = onTrash
        self.showTranslated = false
        self.translatedTexts = [:]
        self.translatedNodes = [:]
        self.onTextNodesExtracted = nil
        self.onScrollProxy = nil
        self.attachmentSummaryStore = nil
        self.attachmentUIStateProvider = { AttachmentUIStateResolver().state(for: $0) }
        self.composerContent = EmptyView()
        self.briefContent = EmptyView()
        self.translationHeader = EmptyView()
    }
}
