import DesignSystem
import SwiftUI

// MARK: - Message Card

struct MessageCardView: View {
    let message: MessageRow
    let showTranslated: Bool
    let translatedText: String?
    let translatedNodes: [String: String]?
    var onTextNodesExtracted: (([TranslationTextNode]) -> Void)?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter
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
            header
            bodyContent
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

    private var header: some View {
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
    }

    @ViewBuilder
    private var bodyContent: some View {
        if showTranslated, message.bodyHtml != nil, translatedNodes != nil || onTextNodesExtracted != nil {
            htmlBody(translatedNodes: translatedNodes, onTextNodesExtracted: onTextNodesExtracted)
        } else if let translated = translatedText, message.bodyHtml == nil {
            Text(translated)
                .font(.rbGeist(14))
                .foregroundStyle(Color.rbFg2)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            htmlBody()
        }
    }

    private func htmlBody(
        translatedNodes: [String: String]? = nil,
        onTextNodesExtracted: (([TranslationTextNode]) -> Void)? = nil
    ) -> some View {
        MessageBodyView(
            bodyHtml: message.bodyHtml,
            bodyText: message.bodyText,
            snippet: message.snippet,
            attachments: message.inlineAttachments.map { attachment in
                HTMLWebView.AttachmentData(
                    contentId: attachment.contentId,
                    mime: attachment.mime,
                    data: Data(base64Encoded: attachment.dataBase64, options: .ignoreUnknownCharacters) ?? Data()
                )
            },
            translatedNodes: translatedNodes,
            onTextNodesExtracted: onTextNodesExtracted
        )
    }
}
