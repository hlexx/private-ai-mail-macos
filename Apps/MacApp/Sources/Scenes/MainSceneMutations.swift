import DesignSystem
import GRDB
import InboxFeature
import Persistence
import SwiftUI

// MARK: - Mutation & Toast Helpers

extension MainScene {

    func archiveSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        Task {
            do {
                try await composition.mailMutator.archive(threadId, accountId: accountId)
                inboxStore.selectedThreadID = nil
                showToast("Archived", undo: .unarchive(threadId: threadId, accountId: accountId))
            } catch {
                showToast("Archive failed", undo: nil)
            }
        }
    }

    func starSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        let isStarred = (try? composition.db.read { db in
            try ThreadLabelRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == threadId && Column("label_id") == "STARRED")
                .fetchOne(db)
        }) != nil
        Task {
            do {
                if isStarred {
                    try await composition.mailMutator.unstar(threadId, accountId: accountId)
                    showToast("Unstarred", undo: .star(threadId: threadId, accountId: accountId))
                } else {
                    try await composition.mailMutator.star(threadId, accountId: accountId)
                    showToast("Starred", undo: .unstar(threadId: threadId, accountId: accountId))
                }
            } catch {
                showToast("Star failed", undo: nil)
            }
        }
    }

    func markReadSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        let markAsRead = thread.hasUnread
        Task {
            do {
                try await composition.mailMutator.markRead(threadId, accountId: accountId, read: markAsRead)
                showToast(markAsRead ? "Marked read" : "Marked unread", undo: nil)
            } catch {
                showToast("Mark read failed", undo: nil)
            }
        }
    }

    func trashThread(_ threadId: String, accountId: String) {
        Task {
            do {
                try await composition.mailMutator.trash(threadId, accountId: accountId)
                if inboxStore.selectedThreadID == threadId {
                    inboxStore.selectedThreadID = nil
                }
                showToast("Trashed", undo: .untrash(threadId: threadId, accountId: accountId))
            } catch {
                showToast("Trash failed", undo: nil)
            }
        }
    }

    func showToast(_ message: String, undo: ToastState.UndoAction?) {
        let toast = ToastState(message: message, undoAction: undo)
        composition.toastMessage = toast
        Task {
            try? await Task.sleep(for: .seconds(8))
            if composition.toastMessage?.id == toast.id {
                composition.toastMessage = nil
            }
        }
    }

    func handleUndo(_ action: ToastState.UndoAction) {
        composition.toastMessage = nil
        Task {
            do {
                switch action {
                case .unarchive(let threadId, let accountId):
                    try await composition.mailMutator.unarchive(threadId, accountId: accountId)
                case .star(let threadId, let accountId):
                    try await composition.mailMutator.star(threadId, accountId: accountId)
                case .unstar(let threadId, let accountId):
                    try await composition.mailMutator.unstar(threadId, accountId: accountId)
                case .untrash(let threadId, let accountId):
                    try await composition.mailMutator.untrash(threadId, accountId: accountId)
                }
            } catch {
                showToast("Undo failed", undo: nil)
            }
        }
    }

    @ViewBuilder
    func toastBar(_ toast: ToastState) -> some View {
        HStack(spacing: RBSpace.s2) {
            RBToast(toast.message, systemImage: "checkmark.circle.fill")
            if toast.undoAction != nil {
                Button("Undo") {
                    if let action = toast.undoAction {
                        handleUndo(action)
                    }
                }
                .buttonStyle(.rbGhost)
            }
        }
    }

    func toggleTheme() {
        let raw = UserDefaults.standard.string(forKey: "rb-theme") ?? RBTheme.system.rawValue
        let current = RBTheme(rawValue: raw) ?? .system
        let next: RBTheme
        switch current {
        case .system: next = .dark
        case .dark: next = .light
        case .light: next = .system
        }
        UserDefaults.standard.set(next.rawValue, forKey: "rb-theme")
    }
}
