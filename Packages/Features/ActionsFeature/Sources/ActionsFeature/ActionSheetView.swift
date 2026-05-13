import DesignSystem
import SwiftUI

// MARK: - Action Model

public enum ActionID: String, CaseIterable, Sendable {
    case reply, snooze, log, task, archive, unsub, rule, share
}

struct ActionItem: Identifiable {
    let id: ActionID
    let label: String
    let color: Color
    let systemName: String

    static let all: [ActionItem] = [
        ActionItem(id: .reply, label: "Draft reply", color: .rbAccent, systemName: "arrowshape.turn.up.left.fill"),
        ActionItem(id: .snooze, label: "Snooze to Fri", color: .rbAccentSecondary, systemName: "clock.fill"),
        ActionItem(id: .log, label: "Log to CRM", color: .rbAccentTertiary, systemName: "arrow.up.forward.square.fill"),
        ActionItem(id: .task, label: "Make a task", color: .rbBurntOrange500, systemName: "diamond.fill"),
        ActionItem(id: .archive, label: "Archive", color: .rbGraphite500, systemName: "archivebox.fill"),
        ActionItem(id: .unsub, label: "Unsubscribe", color: .rbGraphite500, systemName: "xmark.circle.fill"),
        ActionItem(id: .rule, label: "Make a rule", color: .rbGraphite500, systemName: "line.3.horizontal.decrease.circle.fill"),
        ActionItem(id: .share, label: "Share thread", color: .rbGraphite500, systemName: "arrow.up.forward.circle.fill"),
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
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(item.color)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.label)
                    .font(.rbGeist(11.5, weight: .medium))
                    .foregroundStyle(Color.rbFg1)
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
        .onHover { isHovered = $0 }
    }
}

// MARK: - ActionSheetView

public struct ActionSheetView: View {
    let threadSubject: String
    let onClose: () -> Void

    @State private var picked: ActionID = .snooze

    public init(threadSubject: String, onClose: @escaping () -> Void) {
        self.threadSubject = threadSubject
        self.onClose = onClose
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: RBSpace.s2), count: 4)

    public var body: some View {
        ZStack {
            // Backdrop mask
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                Spacer()

                // Sheet card
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            EyebrowLabel("What should I do with this thread?")
                            Text(threadSubject.isEmpty ? "Selected thread" : threadSubject)
                                .rbTextStyle(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.rbFg1)
                        }
                        Spacer()
                        RBIconButton(systemName: "xmark", accessibilityLabel: "Close") {
                            onClose()
                        }
                    }
                    .padding(.bottom, RBSpace.s3)

                    // 4x2 grid
                    LazyVGrid(columns: columns, spacing: RBSpace.s2) {
                        ForEach(ActionItem.all) { item in
                            ActionTile(item: item, isSelected: picked == item.id) {
                                picked = item.id
                            }
                        }
                    }
                    .padding(.bottom, RBSpace.s3)

                    // Preview block
                    VStack(alignment: .leading, spacing: RBSpace.s2) {
                        HStack {
                            Text("◆ Re:Box will".uppercased())
                                .font(.rbMono(10, weight: .medium))
                                .tracking(0.14 * 10)
                                .foregroundStyle(Color.rbSignalSuccess)

                            Spacer()

                            Text("undo in 5s".uppercased())
                                .font(.rbMono(10, weight: .medium))
                                .tracking(0.14 * 10)
                                .foregroundStyle(Color.rbFg3)
                        }

                        Text(previews[picked] ?? "")
                            .rbTextStyle(.bodySM)
                            .foregroundStyle(Color.rbFg2)
                            .lineSpacing(4)

                        Text("on-device · 0 bytes uploaded")
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
                        Button("Cancel") { onClose() }
                            .buttonStyle(.rbGhost)
                        Button("Do it") { onClose() }
                            .buttonStyle(.rbPrimary)
                    }
                    .padding(.top, RBSpace.s3)
                }
                .padding(RBSpace.s4)
                .background(.ultraThickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: RBRadius.xl)
                        .strokeBorder(Color.rbGlassStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.xl))
                .frame(maxWidth: 720)
                .padding(.horizontal, RBSpace.s6)
                .padding(.bottom, RBSpace.s6)
            }
        }
        .onExitCommand { onClose() }
    }
}

#if DEBUG
#Preview("Action Sheet - Dark") {
    ActionSheetView(threadSubject: "Re: Contract draft — Acme GmbH") {}
        .preferredColorScheme(.dark)
}

#Preview("Action Sheet - Light") {
    ActionSheetView(threadSubject: "Re: Contract draft — Acme GmbH") {}
        .preferredColorScheme(.light)
}
#endif
