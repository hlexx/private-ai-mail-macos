import DesignSystem
import SwiftUI

// MARK: - Action Model

public enum ActionID: String, CaseIterable, Sendable {
    case reply
    case archive
    case star
    case markRead
    case trash
    case snooze
    case log
    case task
    case unsub
    case rule
    case share

    var trustMVPAction: TrustMVPAction? {
        switch self {
        case .reply:
            .draftReply
        case .archive:
            .archiveThread
        case .star:
            .starThread
        case .markRead:
            .markRead
        case .trash:
            .trashThread
        case .snooze, .log, .task, .unsub, .rule, .share:
            nil
        }
    }
}

struct ActionItem: Identifiable {
    let id: ActionID
    let label: String
    let color: Color
    let systemName: String

    static let executable: [ActionItem] = [
        ActionItem(
            id: .reply,
            label: String(localized: "action.draftReply", defaultValue: "Draft reply"),
            color: .rbAccent,
            systemName: "arrowshape.turn.up.left.fill"
        ),
        ActionItem(
            id: .archive,
            label: String(localized: "action.archive", defaultValue: "Archive"),
            color: .rbGraphite500,
            systemName: "archivebox.fill"
        ),
        ActionItem(
            id: .star,
            label: String(localized: "action.star", defaultValue: "Star"),
            color: .rbAccentSecondary,
            systemName: "star.fill"
        ),
        ActionItem(
            id: .markRead,
            label: String(localized: "action.markRead", defaultValue: "Mark read"),
            color: .rbAccentTertiary,
            systemName: "envelope.open.fill"
        ),
        ActionItem(
            id: .trash,
            label: String(localized: "action.trash", defaultValue: "Trash"),
            color: .rbBurntOrange500,
            systemName: "trash.fill"
        ),
    ]

    static let roadmap: [ActionItem] = [
        ActionItem(
            id: .snooze,
            label: String(localized: "action.snoozeToFri", defaultValue: "Snooze to Fri"),
            color: .rbGraphite500,
            systemName: "clock"
        ),
        ActionItem(
            id: .log,
            label: String(localized: "action.logCRM", defaultValue: "Log to CRM"),
            color: .rbGraphite500,
            systemName: "arrow.up.forward.square"
        ),
        ActionItem(
            id: .task,
            label: String(localized: "action.makeTask", defaultValue: "Make a task"),
            color: .rbGraphite500,
            systemName: "diamond"
        ),
        ActionItem(
            id: .unsub,
            label: String(localized: "action.unsubscribe", defaultValue: "Unsubscribe"),
            color: .rbGraphite500,
            systemName: "xmark.circle.fill"
        ),
        ActionItem(
            id: .rule,
            label: String(localized: "action.makeRule", defaultValue: "Make a rule"),
            color: .rbGraphite500,
            systemName: "line.3.horizontal.decrease.circle.fill"
        ),
        ActionItem(
            id: .share,
            label: String(localized: "action.shareThread", defaultValue: "Share thread"),
            color: .rbGraphite500,
            systemName: "arrow.up.forward.circle.fill"
        ),
    ]
}

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

// MARK: - Roadmap Tile

struct RoadmapActionTile: View {
    let item: ActionItem

    var body: some View {
        HStack(spacing: RBSpace.s2) {
            Image(systemName: item.systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rbFg3.opacity(0.75))
                .frame(width: 22, height: 22)
                .background(Color.rbBgElev2.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(item.label)
                .font(.rbGeist(11.5, weight: .medium))
                .foregroundStyle(Color.rbFg3)
                .lineLimit(1)

            Spacer(minLength: RBSpace.s2)

            Text(String(localized: "action.roadmap.badge", defaultValue: "Unavailable"))
                .font(.rbMono(9, weight: .medium))
                .foregroundStyle(Color.rbFg3)
        }
        .padding(.vertical, RBSpace.s2)
        .padding(.horizontal, RBSpace.s2)
        .background(Color.rbBgElev2.opacity(0.28))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.md)
                .strokeBorder(Color.rbStroke1.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .help(String(localized: "action.roadmap.help", defaultValue: "Not available in this build"))
        .accessibilityLabel(
            Text(
                String(
                    localized: "action.roadmap.accessibility",
                    defaultValue: "\(item.label), unavailable in this build"
                )
            )
        )
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - ActionSheetView

public struct ActionSheetView: View {
    let threadSubject: String
    let onAction: (ActionID?) -> Void

    @State private var picked: ActionID? = ActionSheetPresentation.defaultSelection

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

                    // Executable action grid
                    LazyVGrid(columns: columns, spacing: RBSpace.s2) {
                        ForEach(ActionItem.executable) { item in
                            ActionTile(
                                item: item,
                                isSelected: picked == item.id,
                                isEnabled: true
                            ) {
                                picked = item.id
                            }
                        }
                    }
                    .padding(.bottom, RBSpace.s3)

                    VStack(alignment: .leading, spacing: RBSpace.s2) {
                        Text(String(localized: "action.roadmap.title", defaultValue: "Unavailable in this build"))
                            .font(.rbMono(10, weight: .medium))
                            .tracking(0.14 * 10)
                            .foregroundStyle(Color.rbFg3)

                        LazyVGrid(columns: columns, spacing: RBSpace.s2) {
                            ForEach(ActionItem.roadmap) { item in
                                RoadmapActionTile(item: item)
                            }
                        }
                    }
                    .padding(.bottom, RBSpace.s3)

                    // Preview block
                    VStack(alignment: .leading, spacing: RBSpace.s2) {
                        HStack {
                            Text(String(localized: "action.preview.eyebrow", defaultValue: "ACTION PREVIEW"))
                                .font(.rbMono(10, weight: .medium))
                                .tracking(0.14 * 10)
                                .foregroundStyle(Color.rbSignalSuccess)

                            Spacer()

                            Text(String(localized: "action.preview.scope", defaultValue: "CURRENT BUILD"))
                                .font(.rbMono(10, weight: .medium))
                                .tracking(0.14 * 10)
                                .foregroundStyle(Color.rbFg3)
                        }

                        Text(ActionSheetPresentation.previewText(for: picked))
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
                        Button(String(localized: "action.cta.doIt", defaultValue: "Do it")) {
                            if let action = ActionSheetPresentation.selectedExecutableAction(picked) {
                                onAction(action)
                            }
                        }
                            .buttonStyle(.rbPrimary)
                            .disabled(!ActionSheetPresentation.isPrimaryCTAEnabled(for: picked))
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
