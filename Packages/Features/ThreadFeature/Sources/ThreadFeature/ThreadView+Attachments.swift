import DesignSystem
import SwiftUI

extension ThreadView {
    // MARK: - Attachment Block

    var attachmentBlock: some View {
        ForEach(store.attachments) { att in
            let summaryState = attachmentSummaryStore?.state(for: att) ?? .idle
            let uiState = summaryState.isWorking ? AttachmentUIState.downloading : attachmentUIStateProvider(att)
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
                        Text(attachmentStatusText(att, uiState: uiState, summaryState: summaryState))
                            .font(.rbMono(11))
                            .foregroundStyle(Color.rbFg3)
                    }

                    Spacer()

                    Button {
                        if let url = uiState.previewURL {
                            AttachmentQuickLookPresenter.shared.preview(url)
                        }
                    } label: {
                        Label(String(localized: "thread.attachment.preview", defaultValue: "Preview"), systemImage: "eye")
                    }
                    .buttonStyle(.rbGhost)
                    .disabled(uiState.previewURL == nil)
                    .help(attachmentPreviewHelp(uiState))

                    Button { attachmentSummaryStore?.summarize(att) } label: {
                        Label(
                            summaryState.isWorking
                                ? String(localized: "thread.attachment.summarizing", defaultValue: "Summarizing")
                                : String(localized: "thread.attachment.summarize", defaultValue: "Summarize"),
                            systemImage: "sparkle"
                        )
                    }
                    .buttonStyle(.rbSecondary)
                    .disabled(!canSummarizeAttachment(att, state: summaryState))
                    .help(attachmentSummaryHelp(att, state: summaryState))
                }

                attachmentStateContent(uiState)
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

    func attachmentStatusText(
        _ attachment: AttachmentInfo,
        uiState: AttachmentUIState,
        summaryState: AttachmentSummaryViewState
    ) -> String {
        let size = attachment.formattedSize.isEmpty ? "File" : attachment.formattedSize
        return "\(size) \u{00B7} \(uiState.statusText) \u{00B7} \(AttachmentSummaryCopy.summaryStatus(for: summaryState))"
    }

    func attachmentPreviewHelp(_ uiState: AttachmentUIState) -> String {
        switch uiState.previewAvailability {
        case .previewAvailable:
            return String(localized: "thread.attachment.preview.help.available", defaultValue: "Preview cached attachment with Quick Look")
        case .unsupportedPreview(let reason):
            return reason
        case .unavailable:
            switch uiState.cacheState {
            case .metadataOnly:
                return String(localized: "thread.attachment.preview.help.metadataOnly", defaultValue: "Download or summarize the attachment before previewing")
            case .downloading:
                return String(localized: "thread.attachment.preview.help.downloading", defaultValue: "Attachment is downloading")
            case .cached:
                return String(localized: "thread.attachment.preview.help.cached", defaultValue: "Preview is not available for this cached attachment")
            case .failed(let message):
                return message
            case .deleted:
                return String(localized: "thread.attachment.preview.help.deleted", defaultValue: "Cached attachment file was deleted")
            }
        }
    }

    func attachmentSummaryHelp(_ attachment: AttachmentInfo, state: AttachmentSummaryViewState) -> String {
        guard attachmentSummaryStore != nil else {
            return String(localized: "thread.attachment.summary.help.unavailable", defaultValue: "Attachment summary is not available")
        }
        guard attachment.hasDownloadIdentity else {
            return String(localized: "thread.attachment.summary.error.missingId", defaultValue: "Attachment is missing a download identifier.")
        }
        if state.isWorking {
            return String(localized: "thread.attachment.summary.loading", defaultValue: "Reading attachment locally...")
        }
        return String(localized: "thread.attachment.summary.help.available", defaultValue: "Summarize with local extracted evidence")
    }

    func canSummarizeAttachment(_ attachment: AttachmentInfo, state: AttachmentSummaryViewState) -> Bool {
        attachmentSummaryStore != nil && attachment.hasDownloadIdentity && !state.isWorking
    }

    @ViewBuilder
    func attachmentStateContent(_ uiState: AttachmentUIState) -> some View {
        if let detailText = uiState.detailText {
            Text(detailText)
                .font(.rbGeist(12))
                .foregroundStyle(Color.rbFg3)
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

enum AttachmentSummaryCopy {
    static func statusText(for attachment: AttachmentInfo, state: AttachmentSummaryViewState) -> String {
        let size = attachment.formattedSize.isEmpty ? "File" : attachment.formattedSize
        return "\(size) \u{00B7} \(summaryStatus(for: state))"
    }

    static func summaryStatus(for state: AttachmentSummaryViewState) -> String {
        switch state {
        case .idle:
            return "ready to summarize"
        case .summarizing:
            return "summarizing locally"
        case .summary(let data):
            return data.cached ? "cached local summary" : "summarized locally"
        case .unsupported:
            return "unsupported"
        case .failed:
            return "summary failed"
        }
    }
}
