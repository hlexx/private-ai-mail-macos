import DesignSystem
import SwiftUI

// MARK: - Tone

public enum ComposeTone: String, CaseIterable, Sendable {
    case concise
    case warm
    case direct
}

// MARK: - InlineComposer

public struct InlineComposer: View {
    @State private var tone: ComposeTone = .warm
    @State private var draftText: String
    let evidence: [String]
    let onEditInFull: () -> Void
    let onSend: () -> Void

    // TODO(§15-step-4): replace with AIKit.draftReply(tone:)
    private static let draftBodies: [ComposeTone: String] = [
        .concise: "Hi Marta \u{2014} yes, I\u{2019}ll send a clean draft by Friday EOD. I\u{2019}ll match the pricing we agreed and flag the two clauses we discussed for your legal team. Stand by.",
        .warm: "Hi Marta \u{2014} thanks for the nudge. I\u{2019}ll have a draft over by Friday EOD; the pricing matches what we agreed, and I\u{2019}ll mark up the two clauses your team raised so legal can move fast next week. Anything else you\u{2019}d like me to include?",
        .direct: "Marta \u{2014} draft by Friday EOD. Pricing per proposal. Two clauses flagged for legal. Confirm if you want SLA terms attached too.",
    ]

    public init(
        evidence: [String] = ["msg_1", "msg_3", "contract.pdf p.2"],
        onEditInFull: @escaping () -> Void = {},
        onSend: @escaping () -> Void = {}
    ) {
        self.evidence = evidence
        self.onEditInFull = onEditInFull
        self.onSend = onSend
        self._draftText = State(initialValue: Self.draftBodies[.warm] ?? "")
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
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            EyebrowLabel(String(localized: "composer.inline.eyebrow", defaultValue: "Draft reply \u{00B7} local"))
            Spacer()
            RBToneSegment(
                segments: ComposeTone.allCases.map { t in
                    RBToneSegment.Segment(
                        id: t,
                        label: t.rawValue.capitalized,
                        detail: Self.wordCount(for: t)
                    )
                },
                selection: $tone
            )
            .onChange(of: tone) { _, newTone in
                // TODO(§15-step-4): replace with AIKit.draftReply(tone:)
                draftText = Self.draftBodies[newTone] ?? ""
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

    // MARK: - Text Area

    private var textArea: some View {
        TextEditor(text: $draftText)
            .font(.rbGeist(14))
            .foregroundStyle(Color.rbFg1)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(minHeight: 130)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.rbBgElev1)
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
            Text("\(evidence.count) citations \u{00B7} \(evidence.joined(separator: " \u{00B7} "))")
        }
        .font(.rbMono(10.5))
        .foregroundStyle(Color.rbFg3)
    }

    private var ctaButtons: some View {
        HStack(spacing: RBSpace.s2) {
            Button {
                // TODO(§15-step-4): replace with AIKit.draftReply(tone:)
                draftText = Self.draftBodies[tone] ?? ""
            } label: {
                Label(String(localized: "composer.cta.regenerate", defaultValue: "Regenerate"), systemImage: "sparkle")
            }
            .buttonStyle(.rbGhost)

            Button(action: onEditInFull) {
                Text(String(localized: "composer.cta.editInFull", defaultValue: "Edit in full"))
            }
            .buttonStyle(.rbSecondary)

            Button(action: onSend) {
                Label(String(localized: "composer.cta.send", defaultValue: "Send"), systemImage: "paperplane.fill")
            }
            .buttonStyle(.rbPrimary)
        }
    }

    // MARK: - Helpers

    private static func wordCount(for tone: ComposeTone) -> String {
        let text = draftBodies[tone] ?? ""
        let count = text.split(separator: " ").count
        return "\(count)w"
    }
}

#if DEBUG
#Preview("Inline Composer") {
    InlineComposer()
        .padding(24)
        .background(Color.rbBgCanvas)
        .frame(width: 600)
        .preferredColorScheme(.dark)
}
#endif
