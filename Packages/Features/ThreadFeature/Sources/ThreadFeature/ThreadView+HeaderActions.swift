import DesignSystem
import SwiftUI

extension ThreadView {
    @ViewBuilder
    var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            fullActionBar
            compactActionBar
        }
    }

    private var fullActionBar: some View {
        HStack(spacing: 4) {
            draftActionButton(compact: false)
            archiveActionButton(compact: false)
            starActionButton(compact: false)
            markReadActionButton(compact: false)
            trashActionButton(compact: false)
            unavailableActionButton(
                title: String(localized: "thread.action.snooze", defaultValue: "Snooze"),
                systemImage: "clock",
                help: String(localized: "thread.action.snooze.help", defaultValue: "Not available yet"),
                compact: false
            )
            unavailableActionButton(
                title: String(localized: "thread.action.sendTo", defaultValue: "Send to"),
                systemImage: "paperplane",
                help: String(localized: "thread.action.sendTo.help", defaultValue: "Not available yet"),
                compact: false
            )
        }
    }

    private var compactActionBar: some View {
        HStack(spacing: 2) {
            draftActionButton(compact: true)
            archiveActionButton(compact: true)
            starActionButton(compact: true)
            markReadActionButton(compact: true)
            trashActionButton(compact: true)
            unavailableActionButton(
                title: String(localized: "thread.action.snooze", defaultValue: "Snooze"),
                systemImage: "clock",
                help: String(localized: "thread.action.snooze.help", defaultValue: "Not available yet"),
                compact: true
            )
            unavailableActionButton(
                title: String(localized: "thread.action.sendTo", defaultValue: "Send to"),
                systemImage: "paperplane",
                help: String(localized: "thread.action.sendTo.help", defaultValue: "Not available yet"),
                compact: true
            )
        }
    }

    private func draftActionButton(compact: Bool) -> some View {
        threadActionButton(
            title: String(localized: "thread.action.draftReply", defaultValue: "Draft"),
            systemImage: "arrowshape.turn.up.left",
            compact: compact,
            disabled: actionTarget == nil
        ) {
            requestActionOrFallback(.draftReply, fallback: nil)
        }
    }

    private func archiveActionButton(compact: Bool) -> some View {
        threadActionButton(
            title: String(localized: "thread.action.archive", defaultValue: "Archive"),
            systemImage: "archivebox",
            compact: compact,
            disabled: actionStore == nil && onArchive == nil
        ) {
            requestActionOrFallback(.archiveThread, fallback: onArchive)
        }
    }

    private func starActionButton(compact: Bool) -> some View {
        threadActionButton(
            title: store.isStarred
                ? String(localized: "thread.action.unstar", defaultValue: "Unstar")
                : String(localized: "thread.action.star", defaultValue: "Star"),
            systemImage: store.isStarred ? "star.fill" : "star",
            compact: compact,
            disabled: actionStore == nil && onStar == nil
        ) {
            if store.isStarred {
                onStar?()
            } else {
                requestActionOrFallback(.starThread, fallback: onStar)
            }
        }
    }

    private func markReadActionButton(compact: Bool) -> some View {
        threadActionButton(
            title: String(localized: "thread.action.markRead", defaultValue: "Mark read"),
            systemImage: "envelope.open",
            compact: compact,
            disabled: actionStore == nil && onMarkRead == nil
        ) {
            requestActionOrFallback(.markRead, fallback: onMarkRead)
        }
    }

    private func trashActionButton(compact: Bool) -> some View {
        threadActionButton(
            title: String(localized: "thread.action.trash", defaultValue: "Trash"),
            systemImage: "trash",
            compact: compact,
            disabled: actionStore == nil && onTrash == nil
        ) {
            requestActionOrFallback(.trashThread, fallback: onTrash)
        }
    }

    private func unavailableActionButton(
        title: String,
        systemImage: String,
        help: String,
        compact: Bool
    ) -> some View {
        threadActionButton(
            title: title,
            systemImage: systemImage,
            compact: compact,
            disabled: true
        ) {}
        .help(help)
    }

    @ViewBuilder
    private func threadActionButton(
        title: String,
        systemImage: String,
        compact: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if compact {
            RBIconButton(systemName: systemImage, accessibilityLabel: title, action: action)
                .disabled(disabled)
                .help(title)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
            }
            .buttonStyle(.rbGhost)
            .disabled(disabled)
            .accessibilityLabel(title)
            .help(title)
        }
    }
}
