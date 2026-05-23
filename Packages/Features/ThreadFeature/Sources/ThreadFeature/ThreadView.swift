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
    var onPreviewAttachment: ((AttachmentInfo) -> Void)?
    var onSummarizeAttachment: ((AttachmentInfo) -> Void)?
    var showTranslated: Bool
    var translatedTexts: [String: String]
    var translatedNodes: [String: [String: String]]
    var onTextNodesExtracted: ((String, [TranslationTextNode]) -> Void)?
    var onScrollProxy: ((ScrollViewProxy) -> Void)?

    public init(
        store: ThreadStore,
        onArchive: (() -> Void)? = nil,
        onStar: (() -> Void)? = nil,
        onPreviewAttachment: ((AttachmentInfo) -> Void)? = nil,
        onSummarizeAttachment: ((AttachmentInfo) -> Void)? = nil,
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
        self.onPreviewAttachment = onPreviewAttachment
        self.onSummarizeAttachment = onSummarizeAttachment
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
            .id(message.id)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Attachment Block

    private var attachmentBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.attachments) { attachment in
                AttachmentCardView(
                    attachment: attachment,
                    onPreview: onPreviewAttachment,
                    onSummarize: onSummarizeAttachment
                )
            }
        }
        .padding(.top, 14)
    }
}

private struct AttachmentCardView: View {
    let attachment: AttachmentInfo
    var onPreview: ((AttachmentInfo) -> Void)?
    var onSummarize: ((AttachmentInfo) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AttachmentThumbnailView(attachment: attachment)

                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.filename)
                        .font(.rbGeist(13, weight: .medium))
                        .foregroundStyle(Color.rbFg1)
                        .lineLimit(2)
                    Text(attachment.metadataDisplayText)
                        .font(.rbMono(11))
                        .foregroundStyle(Color.rbFg3)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button { onPreview?(attachment) } label: {
                        Label(String(localized: "thread.attachment.preview", defaultValue: "Preview"), systemImage: "eye")
                    }
                    .buttonStyle(.rbGhost)
                    .disabled(!attachment.canPreviewAttachment(hasHandler: onPreview != nil))

                    Button { onSummarize?(attachment) } label: {
                        Label(String(localized: "thread.attachment.summarize", defaultValue: "Summarize"), systemImage: "sparkle")
                    }
                    .buttonStyle(.rbSecondary)
                    .disabled(!attachment.canSummarizeAttachment(hasHandler: onSummarize != nil))
                }
            }

            AttachmentStateStackView(attachment: attachment)

            if case .available(let summary) = attachment.summaryState {
                AttachmentSummaryPanel(summary: summary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.md)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
    }
}

private struct AttachmentThumbnailView: View {
    let attachment: AttachmentInfo

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: RBRadius.xs)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.rbSignalAttachBg.opacity(0.78),
                            Color.rbBgElev2
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 38, height: 48)
            Text(attachment.fileBadgeText)
                .font(.rbMono(8, weight: .semibold))
                .foregroundStyle(Color.rbFg1)
                .padding(.leading, 4)
                .padding(.bottom, 4)
        }
    }
}

private struct AttachmentStateStackView: View {
    let attachment: AttachmentInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AttachmentStatusLineView(
                systemName: attachment.hasLocalFile ? "externaldrive.fill" : "externaldrive.badge.xmark",
                text: attachment.localFileStatusText,
                tint: attachment.hasLocalFile ? Color.rbSignalSuccess : Color.rbFg3
            )
            AttachmentStatusLineView(
                systemName: extractionIconName,
                text: attachment.extractionStatusText,
                tint: extractionTint
            )
            AttachmentStatusLineView(
                systemName: summaryIconName,
                text: attachment.summaryStatusText,
                tint: summaryTint
            )
        }
    }

    private var extractionIconName: String {
        switch attachment.extractionState {
        case .succeeded:
            return "text.page.fill"
        case .unsupported:
            return "nosign"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .running:
            return "gearshape.fill"
        case .pending:
            return "clock.fill"
        case .waitingForLocalFile:
            return "text.page"
        }
    }

    private var extractionTint: Color {
        switch attachment.extractionState {
        case .succeeded:
            return .rbSignalSuccess
        case .unsupported, .failed:
            return .rbSignalDeadline
        case .running, .pending:
            return .rbSignalAttach
        case .waitingForLocalFile:
            return .rbFg3
        }
    }

    private var summaryIconName: String {
        switch attachment.summaryState {
        case .available:
            return "sparkle"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "sparkles"
        }
    }

    private var summaryTint: Color {
        switch attachment.summaryState {
        case .available:
            return .rbSignalLocalAi
        case .failed:
            return .rbSignalDeadline
        case .unavailable:
            return .rbFg3
        }
    }
}

private struct AttachmentStatusLineView: View {
    let systemName: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(text)
                .font(.rbMono(10.5))
                .foregroundStyle(Color.rbFg3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AttachmentSummaryPanel: View {
    let summary: AttachmentSummaryViewData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(Color.rbStroke1)

            HStack(spacing: 8) {
                Text("Local summary")
                    .font(.rbMono(10, weight: .semibold))
                    .foregroundStyle(Color.rbSignalLocalAi)
                    .textCase(.uppercase)
                Text(summary.confidenceDisplayText)
                    .font(.rbMono(10))
                    .foregroundStyle(Color.rbFg3)
            }

            Text(summary.summary)
                .font(.rbGeist(12.5))
                .foregroundStyle(Color.rbFg2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.keyFields.isEmpty {
                AttachmentSummaryKeyFieldsView(fields: summary.keyFields)
            }

            if !summary.risks.isEmpty {
                AttachmentSummaryFindingsView(title: "Risks", findings: summary.risks)
            }

            if !summary.nextSteps.isEmpty {
                AttachmentSummaryFindingsView(title: "Next steps", findings: summary.nextSteps)
            }

            Text(summary.evidenceDisplayText)
                .font(.rbMono(10))
                .foregroundStyle(summary.evidenceChunkIds.isEmpty ? Color.rbFg3 : Color.rbSignalAttach)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AttachmentSummaryKeyFieldsView: View {
    let fields: [AttachmentSummaryKeyFieldViewData]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AttachmentSummarySectionTitleView(title: "Key fields")
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(field.label): \(field.value)")
                        .font(.rbGeist(12, weight: .medium))
                        .foregroundStyle(Color.rbFg1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AttachmentSummaryViewData.evidenceText(for: field.evidenceChunkIds))
                        .font(.rbMono(10))
                        .foregroundStyle(Color.rbFg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct AttachmentSummaryFindingsView: View {
    let title: String
    let findings: [AttachmentSummaryFindingViewData]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AttachmentSummarySectionTitleView(title: title)
            ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.text)
                        .font(.rbGeist(12))
                        .foregroundStyle(Color.rbFg2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AttachmentSummaryViewData.evidenceText(for: finding.evidenceChunkIds))
                        .font(.rbMono(10))
                        .foregroundStyle(Color.rbFg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct AttachmentSummarySectionTitleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.rbMono(10, weight: .semibold))
            .foregroundStyle(Color.rbFg3)
            .textCase(.uppercase)
    }
}

extension ThreadView where ComposerContent == EmptyView, BriefContent == EmptyView, TranslationHeader == EmptyView {
    public init(
        store: ThreadStore,
        onArchive: (() -> Void)? = nil,
        onStar: (() -> Void)? = nil,
        onPreviewAttachment: ((AttachmentInfo) -> Void)? = nil,
        onSummarizeAttachment: ((AttachmentInfo) -> Void)? = nil
    ) {
        self.store = store
        self.onArchive = onArchive
        self.onStar = onStar
        self.onPreviewAttachment = onPreviewAttachment
        self.onSummarizeAttachment = onSummarizeAttachment
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
