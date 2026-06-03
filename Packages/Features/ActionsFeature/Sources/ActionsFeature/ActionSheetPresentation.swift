import Foundation

public enum ActionExecutionSupport {
    public static func isEnabled(_ action: ActionID) -> Bool {
        action.trustMVPAction != nil
    }

    static func preview(for action: ActionID) -> String? {
        guard isEnabled(action) else { return nil }
        return previews[action]
    }
}

enum ActionSheetPresentation {
    static let defaultSelection: ActionID? = nil

    static func selectedExecutableAction(_ selection: ActionID?) -> ActionID? {
        guard let selection, ActionExecutionSupport.isEnabled(selection) else {
            return nil
        }
        return selection
    }

    static func isPrimaryCTAEnabled(for selection: ActionID?) -> Bool {
        selectedExecutableAction(selection) != nil
    }

    static func previewText(for selection: ActionID?) -> String {
        guard
            let action = selectedExecutableAction(selection),
            let preview = ActionExecutionSupport.preview(for: action)
        else {
            return String(
                localized: "action.preview.empty",
                defaultValue: "Select an available action to preview the exact mailbox update."
            )
        }
        return preview
    }
}

private let previews: [ActionID: String] = [
    .reply: "Draft reply opens a confirmation step before any draft is written.",
    .archive: "Archive queues the selected thread for Gmail archive.",
    .star: "Star queues a Gmail star update for this thread.",
    .markRead: "Mark read queues a Gmail read-state update for this thread.",
    .trash: "Trash opens a confirmation step before moving the thread to trash.",
]
