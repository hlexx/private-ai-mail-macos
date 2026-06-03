import ActionsFeature
import DesignSystem
import SwiftUI

public enum ThreadViewAnchor: Hashable {
    case head
    case composer
}

enum ThreadBottomPanelTab: String {
    case draft
    case brief
}

public struct ThreadView<ComposerContent: View, BriefContent: View, TranslationHeader: View>: View {
    let store: ThreadStore
    let composerContent: ComposerContent
    let briefContent: BriefContent
    let translationHeader: TranslationHeader
    let showsComposerPanel: Bool
    let showsBriefInBottomPanel: Bool
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
    @AppStorage("pam.layout.threadBottomPanelCollapsed") var bottomPanelCollapsed: Bool = false
    @AppStorage("pam.layout.threadBottomPanelTab") var bottomPanelTabRaw: String = ThreadBottomPanelTab.draft.rawValue

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
        showsComposerPanel: Bool = true,
        showsBriefInBottomPanel: Bool = false,
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
        self.showsComposerPanel = showsComposerPanel
        self.showsBriefInBottomPanel = showsBriefInBottomPanel
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
                    ScrollViewReader { proxy in
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 0) {
                                        threadColumn
                                        if store.hasAttachment {
                                            attachmentBlock
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.top, 12)
                                    .padding(.bottom, hasBottomPanel ? 16 : 24)
                                }
                                .onAppear { onScrollProxy?(proxy) }

                                if hasBottomPanel {
                                    bottomWorkPanel(availableHeight: geometry.size.height)
                                        .id(ThreadViewAnchor.composer)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.subject)
                    .rbTextStyle(.h2)
                    .foregroundStyle(Color.rbFg1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                metaLine
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            actionBar
                .padding(.top, 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
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
        self.showsComposerPanel = false
        self.showsBriefInBottomPanel = false
        self.onTextNodesExtracted = nil
        self.onScrollProxy = nil
        self.attachmentSummaryStore = nil
        self.attachmentUIStateProvider = { AttachmentUIStateResolver().state(for: $0) }
        self.composerContent = EmptyView()
        self.briefContent = EmptyView()
        self.translationHeader = EmptyView()
    }
}
