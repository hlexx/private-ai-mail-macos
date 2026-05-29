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
    var attachmentSummaryStore: AttachmentSummaryStore?

    public init(
        store: ThreadStore,
        onArchive: (() -> Void)? = nil,
        onStar: (() -> Void)? = nil,
        showTranslated: Bool = false,
        translatedTexts: [String: String] = [:],
        translatedNodes: [String: [String: String]] = [:],
        onTextNodesExtracted: ((String, [TranslationTextNode]) -> Void)? = nil,
        onScrollProxy: ((ScrollViewProxy) -> Void)? = nil,
        attachmentSummaryStore: AttachmentSummaryStore? = nil,
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
        self.attachmentSummaryStore = attachmentSummaryStore
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

private extension ThreadView {
    // MARK: - Attachment Block

    var attachmentBlock: some View {
        ForEach(store.attachments) { att in
            let summaryState = attachmentSummaryStore?.state(for: att) ?? .idle
            VStack(alignment: .leading, spacing: 10) {
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
                        Text(attachmentStatusText(att, state: summaryState))
                            .font(.rbMono(11))
                            .foregroundStyle(Color.rbFg3)
                    }

                    Spacer()

                    Button {} label: {
                        Label(String(localized: "thread.attachment.preview", defaultValue: "Preview"), systemImage: "eye")
                    }
                    .buttonStyle(.rbGhost)
                    .disabled(true)
                    .help(String(localized: "thread.attachment.open.help", defaultValue: "Attachment opening is not available yet"))

                    Button { attachmentSummaryStore?.summarize(att) } label: {
                        Label(
                            summaryState.isWorking
                                ? String(localized: "thread.attachment.summarizing", defaultValue: "Summarizing")
                                : String(localized: "thread.attachment.summarize", defaultValue: "Summarize"),
                            systemImage: "sparkle"
                        )
                    }
                    .buttonStyle(.rbSecondary)
                    .disabled(attachmentSummaryStore == nil || summaryState.isWorking)
                }

                attachmentSummaryContent(summaryState)
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

    func attachmentStatusText(_ attachment: AttachmentInfo, state: AttachmentSummaryViewState) -> String {
        let size = attachment.formattedSize.isEmpty ? "File" : attachment.formattedSize
        switch state {
        case .idle:
            return "\(size) \u{00B7} local summary ready"
        case .summarizing:
            return "\(size) \u{00B7} summarizing locally"
        case .summary(let data):
            return data.cached
                ? "\(size) \u{00B7} cached local summary"
                : "\(size) \u{00B7} summarized locally"
        case .unsupported:
            return "\(size) \u{00B7} unsupported"
        case .failed:
            return "\(size) \u{00B7} summary failed"
        }
    }

    @ViewBuilder
    func attachmentSummaryContent(_ state: AttachmentSummaryViewState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .summarizing:
            Text(String(localized: "thread.attachment.summary.loading", defaultValue: "Reading attachment locally..."))
                .font(.rbGeist(12))
                .foregroundStyle(Color.rbFg3)
        case .summary(let data):
            VStack(alignment: .leading, spacing: 8) {
                Text(data.summary)
                    .font(.rbGeist(13, weight: .medium))
                    .foregroundStyle(Color.rbFg1)
                if !data.keyFields.isEmpty {
                    Text(data.keyFields.map { "\($0.name): \($0.value)" }.joined(separator: " \u{00B7} "))
                        .font(.rbMono(11))
                        .foregroundStyle(Color.rbFg2)
                }
                if let evidence = data.evidence.first {
                    Text("\(String(localized: "thread.attachment.summary.evidence", defaultValue: "Evidence:")) \(evidence.quote)")
                        .font(.rbMono(11))
                        .foregroundStyle(Color.rbFg3)
                        .lineLimit(2)
                }
            }
        case .unsupported(let reason):
            Text(reason)
                .font(.rbGeist(12))
                .foregroundStyle(Color.rbFg3)
        case .failed(let message):
            Text(message)
                .font(.rbGeist(12))
                .foregroundStyle(Color.rbFg3)
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
        self.attachmentSummaryStore = nil
        self.composerContent = EmptyView()
        self.briefContent = EmptyView()
        self.translationHeader = EmptyView()
    }
}
