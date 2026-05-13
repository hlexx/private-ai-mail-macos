import SwiftUI

/// A chip displaying thread signal metadata (reply, due, attachment, etc.).
/// Each variant maps to the corresponding `rbSignal*` color/background pair.
public struct SignalChip: View {
    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public enum Kind: Hashable, Sendable {
        case due(label: String, urgent: Bool = false)
        case reply(label: String)
        case att(pages: Int?)
        case ai(label: String)
        case logged(target: String)
        case cc(label: String)
        case cal(label: String)
        case paid(label: String)
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 8, weight: .semibold))
            Text(displayLabel)
                .rbTextStyle(.eyebrow)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(backgroundColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch kind {
        case .due: return "clock.fill"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .att: return "paperclip"
        case .ai: return "sparkle"
        case .logged: return "checkmark.circle.fill"
        case .cc: return "person.2.fill"
        case .cal: return "calendar"
        case .paid: return "dollarsign.circle.fill"
        }
    }

    private var displayLabel: String {
        switch kind {
        case .due(let label, _): return label
        case .reply(let label): return label
        case .att(let pages):
            if let pages { return "\(pages)p" }
            return "att"
        case .ai(let label): return label
        case .logged(let target): return target
        case .cc(let label): return label
        case .cal(let label): return label
        case .paid(let label): return label
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .due(_, let urgent):
            return urgent ? .rbToneCoral600 : .rbSignalDeadline
        case .reply: return .rbSignalReply
        case .att: return .rbSignalAttach
        case .ai: return .rbSignalLocalAi
        case .logged: return .rbSignalSuccess
        case .cc: return .rbFg3
        case .cal: return .rbSignalDeadline
        case .paid: return .rbSignalSuccess
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .due: return .rbSignalDeadlineBg
        case .reply: return .rbSignalReplyBg
        case .att: return .rbSignalAttachBg
        case .ai: return .rbSignalLocalAiBg
        case .logged: return .rbSignalSuccessBg
        case .cc: return .rbBgElev2
        case .cal: return .rbSignalDeadlineBg
        case .paid: return .rbSignalSuccessBg
        }
    }
}

#if DEBUG
#Preview("Signal Chips") {
    VStack(spacing: 8) {
        HStack(spacing: 6) {
            SignalChip(kind: .due(label: "Fri", urgent: false))
            SignalChip(kind: .due(label: "Overdue", urgent: true))
            SignalChip(kind: .reply(label: "Reply"))
            SignalChip(kind: .att(pages: 4))
        }
        HStack(spacing: 6) {
            SignalChip(kind: .ai(label: "AI"))
            SignalChip(kind: .logged(target: "CRM"))
            SignalChip(kind: .cc(label: "CC'd"))
            SignalChip(kind: .cal(label: "Tue"))
            SignalChip(kind: .paid(label: "Paid"))
        }
    }
    .padding()
    .background(Color.rbBgCanvas)
    .preferredColorScheme(.dark)
}
#endif
