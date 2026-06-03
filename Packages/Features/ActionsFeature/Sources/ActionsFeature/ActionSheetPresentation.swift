import Foundation

public enum ActionExecutionAvailability: Sendable, Equatable {
    case supported
    case unsupportedProvider

    var allowsExecution: Bool {
        self == .supported
    }
}

public enum ActionExecutionSupport {
    public static func isEnabled(
        _ action: ActionID,
        availability: ActionExecutionAvailability = .supported
    ) -> Bool {
        availability.allowsExecution && action.trustMVPAction != nil
    }

    static func preview(for action: ActionID, availability: ActionExecutionAvailability = .supported) -> String? {
        guard isEnabled(action, availability: availability) else { return nil }
        return previews[action]
    }
}

enum ActionSheetPresentation {
    static func selectedTrustAction(
        _ selection: ActionID?,
        availability: ActionExecutionAvailability = .supported
    ) -> TrustMVPAction? {
        guard availability.allowsExecution, let action = selection?.trustMVPAction else {
            return nil
        }
        return action
    }

    static func isPrimaryCTAEnabled(
        for selection: ActionID?,
        availability: ActionExecutionAvailability = .supported
    ) -> Bool {
        selectedTrustAction(selection, availability: availability) != nil
    }

    static func previewText(
        for selection: ActionID?,
        availability: ActionExecutionAvailability = .supported
    ) -> String {
        guard availability.allowsExecution else {
            return String(
                localized: "action.preview.unsupportedProvider",
                defaultValue: "Trust MVP mailbox actions are Gmail-only in this build."
            )
        }
        guard
            let selection,
            let preview = ActionExecutionSupport.preview(for: selection, availability: availability)
        else {
            return String(
                localized: "action.preview.empty",
                defaultValue: "Select an available action to preview the exact mailbox update."
            )
        }
        return preview
    }

    static func privacyText(
        for selection: ActionID?,
        availability: ActionExecutionAvailability = .supported
    ) -> String {
        guard availability.allowsExecution else {
            return String(
                localized: "action.preview.privacy.unsupportedProvider",
                defaultValue: "No provider update will run for this account in this build."
            )
        }
        guard selectedTrustAction(selection, availability: availability) != nil else {
            return String(
                localized: "action.preview.privacy.empty",
                defaultValue: "No provider update runs until you choose an available action."
            )
        }
        return String(
            localized: "action.preview.privacy.gmail",
            defaultValue: "Gmail receives action metadata for the selected thread only when the action is queued."
        )
    }
}

private let previews: [ActionID: String] = [
    .reply: "Draft reply opens a confirmation step before any Gmail draft is written.",
    .archive: "Archive queues a Gmail archive update for the selected thread.",
    .star: "Star queues a Gmail star update for the selected thread.",
    .markRead: "Mark read queues a Gmail read-state update for the selected thread.",
    .trash: "Trash opens a confirmation step before moving the thread to Gmail trash.",
]
