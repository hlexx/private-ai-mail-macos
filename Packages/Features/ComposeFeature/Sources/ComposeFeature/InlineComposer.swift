import AIKit
import DesignSystem
import SwiftUI

// MARK: - InlineComposer

public struct InlineComposer: View {
    @State private var tone: AIReplyTone = .warm
    @State private var draftText: String = ""
    @State private var detectedLanguage: String?

    let threadID: String
    let replyLanguage: String?
    let replyStore: ReplyStore
    let onEditInFull: (String) -> Void
    let onSend: (String) -> Void

    public init(
        threadID: String,
        replyLanguage: String? = nil,
        replyStore: ReplyStore,
        onEditInFull: @escaping (String) -> Void = { _ in },
        onSend: @escaping (String) -> Void = { _ in }
    ) {
        self.threadID = threadID
        self.replyLanguage = replyLanguage
        self.replyStore = replyStore
        self.onEditInFull = onEditInFull
        self.onSend = onSend
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerRow
            textArea
            footerRow
        }
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.lg)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .padding(.top, 18)
        .task {
            replyStore.generate(threadID: threadID, tone: tone, replyLanguage: replyLanguage)
        }
        .onChange(of: replyStore.reply) { _, newReply in
            if let newReply {
                draftText = newReply.body
                detectedLanguage = newReply.detectedReplyLanguage
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            eyebrowLabel
            Spacer()
            RBToneSegment(
                segments: AIReplyTone.allCases.map { t in
                    RBToneSegment.Segment(
                        id: t,
                        label: t.rawValue.capitalized,
                        detail: ""
                    )
                },
                selection: $tone
            )
            .onChange(of: tone) { _, newTone in
                replyStore.generate(threadID: threadID, tone: newTone, replyLanguage: replyLanguage)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }

    private var eyebrowLabel: some View {
        HStack(spacing: 4) {
            EyebrowLabel(eyebrowText)
        }
    }

    private var eyebrowText: String {
        var parts = ["Draft reply", "local"]
        if let lang = detectedLanguage {
            parts.append("in \(lang.uppercased())")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Text Area

    private var textArea: some View {
        ZStack {
            TextEditor(text: $draftText)
                .font(.rbGeist(14))
                .foregroundStyle(Color.rbFg1)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(minHeight: 130, maxHeight: 260)
                .background(Color.rbBgElev1)
                .opacity(replyStore.isLoading ? 0.4 : 1.0)

            if replyStore.isLoading {
                Text("Drafting\u{2026}")
                    .font(.rbGeist(14))
                    .foregroundStyle(Color.rbFg3)
            }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            citationsLine
            Spacer()
            ctaButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.rbBgCanvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }

    private var citationsLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            if let reply = replyStore.reply, !reply.evidenceMessageIDs.isEmpty {
                Text("\(reply.evidenceMessageIDs.count) citations \u{00B7} \(reply.evidenceMessageIDs.joined(separator: " \u{00B7} "))")
            } else {
                Text("On-device AI")
            }
        }
        .font(.rbMono(10.5))
        .foregroundStyle(Color.rbFg3)
    }

    private var ctaButtons: some View {
        HStack(spacing: RBSpace.s2) {
            Button {
                replyStore.regenerate(threadID: threadID, tone: tone, replyLanguage: replyLanguage)
            } label: {
                Label(String(localized: "composer.cta.regenerate", defaultValue: "Regenerate"), systemImage: "sparkle")
            }
            .buttonStyle(.rbGhost)

            Button {
                onEditInFull(draftText)
            } label: {
                Text(String(localized: "composer.cta.editInFull", defaultValue: "Edit in full"))
            }
            .buttonStyle(.rbSecondary)

            Button {
                onSend(draftText)
            } label: {
                Label(String(localized: "composer.cta.send", defaultValue: "Send"), systemImage: "paperplane.fill")
            }
            .buttonStyle(.rbPrimary)
        }
    }
}

#if DEBUG
#Preview("Inline Composer") {
    InlineComposer(
        threadID: "preview-thread",
        replyStore: ReplyStore()
    )
    .padding(24)
    .background(Color.rbBgCanvas)
    .frame(width: 600)
    .preferredColorScheme(.dark)
}
#endif
