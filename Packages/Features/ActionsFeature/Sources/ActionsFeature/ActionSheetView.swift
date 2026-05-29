import DesignSystem
import SwiftUI

// MARK: - Action Model

public enum ActionID: String, CaseIterable, Sendable {
    case reply, snooze, log, task, archive, unsub, rule, share
}

public enum ActionExecutionSupport {
    public static func isEnabled(_ action: ActionID) -> Bool {
        switch action {
        case .reply, .archive:
            return true
        case .snooze, .log, .task, .unsub, .rule, .share:
            return false
        }
    }

    static func preview(for action: ActionID) -> String {
        previews[action] ?? ""
    }
}

struct ActionItem: Identifiable {
    let id: ActionID
    let label: String
    let color: Color
    let systemName: String

    static let all: [ActionItem] = [
        ActionItem(id: .reply, label: String(localized: "action.draftReply", defaultValue: "Draft reply"), color: .rbAccent, systemName: "arrowshape.turn.up.left.fill"),
        ActionItem(id: .snooze, label: String(localized: "action.snoozeToFri", defaultValue: "Snooze to Fri"), color: .rbAccentSecondary, systemName: "clock.fill"),
        ActionItem(id: .log, label: String(localized: "action.logCRM", defaultValue: "Log to CRM"), color: .rbAccentTertiary, systemName: "arrow.up.forward.square.fill"),
        ActionItem(id: .task, label: String(localized: "action.makeTask", defaultValue: "Make a task"), color: .rbBurntOrange500, systemName: "diamond.fill"),
        ActionItem(id: .archive, label: String(localized: "action.archive", defaultValue: "Archive"), color: .rbGraphite500, systemName: "archivebox.fill"),
        ActionItem(id: .unsub, label: String(localized: "action.unsubscribe", defaultValue: "Unsubscribe"), color: .rbGraphite500, systemName: "xmark.circle.fill"),
        ActionItem(id: .rule, label: String(localized: "action.makeRule", defaultValue: "Make a rule"), color: .rbGraphite500, systemName: "line.3.horizontal.decrease.circle.fill"),
        ActionItem(id: .share, label: String(localized: "action.shareThread", defaultValue: "Share thread"), color: .rbGraphite500, systemName: "arrow.up.forward.circle.fill"),
    ]
}

// MARK: - Preview Text

private let previews: [ActionID: String] = [
    .reply: "I'll draft a reply matching your tone and ask for the contract attachment.",
    .snooze: "Thread will resurface Friday at 9:00 AM, with the brief pre-loaded.",
    .log: "I'll push the summary and two action items to HubSpot under Acme GmbH.",
    .task: "I'll create 'Send contract draft to Marta' due Fri, linked to this thread.",
    .archive: "Thread is archived. Re:Box keeps the summary searchable.",
    .unsub: "Re:Box will unsubscribe and filter future mail from this sender.",
    .rule: "Suggested rule: From: marta@acme.de → label 'Acme · Contracts'.",
    .share: "Generate a one-time link to share the brief with your team.",
]

// MARK: - Action Tile

struct ActionTile: View {
    let item: ActionItem
    let isSelected: Bool
    let isEnabled: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    private var tileBackground: Color {
        isSelected ? Color.rbAccent.opacity(0.10) : Color.rbBgElev1
    }

    private var borderColor: Color {
        (isSelected || isHovered) ? Color.rbAccent : Color.rbStroke1
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: RBSpace.s2) {
                Image(systemName: item.systemName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isEnabled ? Color.white : Color.rbFg3)
                    .frame(width: 28, height: 28)
                    .background(isEnabled ? item.color : Color.rbBgElev2)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.label)
                    .font(.rbGeist(11.5, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.rbFg1 : Color.rbFg3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, RBSpace.s3)
            .padding(.horizontal, RBSpace.s2)
            .background(tileBackground)
            .overlay(
                RoundedRectangle(cornerRadius: RBRadius.md)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isEnabled ? item.label : String(localized: "action.unavailable.help", defaultValue: "Not available yet"))
        .onHover { isHovered = $0 }
    }
}

// MARK: - ActionSheetView

public struct ActionSheetView: View {
    let threadSubject: String
    let onAction: (ActionID?) -> Void

    @State private var picked: ActionID = .reply

    public init(threadSubject: String, onAction: @escaping (ActionID?) -> Void) {
        self.threadSubject = threadSubject
        self.onAction = onAction
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: RBSpace.s2), count: 4)

    public var body: some View {
        ZStack {
            // Backdrop mask
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onAction(nil) }

            VStack {
                Spacer()

                // Sheet card
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            EyebrowLabel(String(localized: "action.sheet.eyebrow", defaultValue: "What should I do with this thread?"))
                            Text(threadSubject.isEmpty ? String(localized: "action.fallbackSubject", defaultValue: "Selected thread") : threadSubject)
                                .rbTextStyle(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.rbFg1)
                        }
                        Spacer()
                        RBIconButton(systemName: "xmark", accessibilityLabel: String(localized: "action.sheet.close", defaultValue: "Close")) {
                            onAction(nil)
                        }
                    }
                    .padding(.bottom, RBSpace.s3)

                    // 4x2 grid
                    LazyVGrid(columns: columns, spacing: RBSpace.s2) {
                        ForEach(ActionItem.all) { item in
                            ActionTile(
                                item: item,
                                isSelected: picked == item.id,
                                isEnabled: ActionExecutionSupport.isEnabled(item.id)
                            ) {
                                picked = item.id
                            }
                        }
                    }
                    .padding(.bottom, RBSpace.s3)

                    // Preview block
                    VStack(alignment: .leading, spacing: RBSpace.s2) {
                        HStack {
                            Text(String(localized: "action.preview.eyebrow", defaultValue: "◆ RE:BOX WILL"))
                                .font(.rbMono(10, weight: .medium))
                                .tracking(0.14 * 10)
                                .foregroundStyle(Color.rbSignalSuccess)

                            Spacer()

                            Text(String(localized: "action.preview.undo", defaultValue: "UNDO IN 5S"))
                                .font(.rbMono(10, weight: .medium))
                                .tracking(0.14 * 10)
                                .foregroundStyle(Color.rbFg3)
                        }

                        Text(ActionExecutionSupport.preview(for: picked))
                            .rbTextStyle(.bodySM)
                            .foregroundStyle(Color.rbFg2)
                            .lineSpacing(4)

                        Text(String(localized: "action.preview.privacy", defaultValue: "on-device · 0 bytes uploaded"))
                            .font(.rbMono(10.5))
                            .foregroundStyle(Color.rbFg3)
                            .padding(.top, RBSpace.s1)
                    }
                    .padding(RBSpace.s3)
                    .background(Color.rbBgElev1)
                    .overlay(
                        RoundedRectangle(cornerRadius: RBRadius.md)
                            .strokeBorder(Color.rbStroke1, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))

                    // CTA row
                    HStack {
                        Spacer()
                        Button(String(localized: "action.cta.cancel", defaultValue: "Cancel")) { onAction(nil) }
                            .buttonStyle(.rbGhost)
                        Button(String(localized: "action.cta.doIt", defaultValue: "Do it")) { onAction(picked) }
                            .buttonStyle(.rbPrimary)
                            .disabled(!ActionExecutionSupport.isEnabled(picked))
                    }
                    .padding(.top, RBSpace.s3)
                }
                .padding(RBSpace.s4)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.xl)
                        .strokeBorder(Color.rbGlassStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.xl))
                .frame(maxWidth: 720)
                .padding(.horizontal, RBSpace.s6)

                Spacer()
            }
        }
        .background(
            Button("") { onAction(nil) }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }
}

#if DEBUG
#Preview("Action Sheet - Dark") {
    ActionSheetView(threadSubject: "Re: Contract draft — Acme GmbH") { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Action Sheet - Light") {
    ActionSheetView(threadSubject: "Re: Contract draft — Acme GmbH") { _ in }
        .preferredColorScheme(.light)
}
#endif
