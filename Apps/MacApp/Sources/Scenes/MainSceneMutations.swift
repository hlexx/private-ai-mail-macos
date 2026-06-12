import ActionsFeature
import DesignSystem
import GRDB
import InboxFeature
import MailDomain
import MailSync
import Persistence
import SwiftUI

// Owns app-shell mailbox mutation and toast side effects. Supervised mutations
// should enter through TrustActionUIStore when supported; direct MailMutating
// calls here are the existing guarded fallback path.
// MARK: - Mutation & Toast Helpers

extension MainScene {
    func moveBriefToBottom() {
        briefPlacementRaw = BriefPanelPlacement.bottom.rawValue
        briefCollapsed = true
        bottomPanelCollapsed = false
        bottomPanelTabRaw = "brief"
    }

    func moveBriefToSide() {
        briefPlacementRaw = BriefPanelPlacement.side.rawValue
        briefCollapsed = false
        bottomPanelTabRaw = "draft"
    }

    func requestTrustActionForSelectedThread(_ action: TrustMVPAction) {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        Task {
            await composition.trustActionStore.requestAction(TrustActionRequest(
                action: action,
                target: TrustActionTarget(
                    accountId: thread.accountId,
                    threadId: thread.id,
                    subject: thread.subject
                )
            ))
        }
    }

    func archiveSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        archiveThread(threadId, accountId: thread.accountId, clearsSelectionOnDirectSuccess: true)
    }

    func archiveThread(
        _ threadId: String,
        accountId: String,
        clearsSelectionOnDirectSuccess: Bool = false
    ) {
        if let thread = threadRow(threadID: threadId, accountId: accountId),
           requestTrustActionIfSupported(.archiveThread, thread: thread) {
            return
        }
        Task {
            do {
                try await composition.mailMutator.archive(threadId, accountId: accountId)
                if clearsSelectionOnDirectSuccess {
                    inboxStore.selectedThreadID = nil
                }
                showToast("Archived", undo: .unarchive(threadId: threadId, accountId: accountId))
            } catch {
                showMutationError(error, fallback: "Archive failed")
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
        if !isStarred, requestTrustActionIfSupported(.starThread, thread: thread) {
            return
        }
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
                showMutationError(error, fallback: "Star failed")
            }
        }
    }

    func markReadSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        if requestTrustActionIfSupported(.markRead, thread: thread) {
            return
        }
        Task {
            do {
                try await composition.mailMutator.markRead(threadId, accountId: accountId, read: true)
                showToast("Marked read", undo: nil)
            } catch {
                showMutationError(error, fallback: "Mark read failed")
            }
        }
    }

    func trashThread(_ threadId: String, accountId: String) {
        if let thread = inboxStore.threads.first(where: { $0.id == threadId }),
           requestTrustActionIfSupported(.trashThread, thread: thread) {
            return
        }
        Task {
            do {
                try await composition.mailMutator.trash(threadId, accountId: accountId)
                if inboxStore.selectedThreadID == threadId {
                    inboxStore.selectedThreadID = nil
                }
                showToast("Trashed", undo: .untrash(threadId: threadId, accountId: accountId))
            } catch {
                showMutationError(error, fallback: "Trash failed")
            }
        }
    }

    private func requestTrustActionIfSupported(_ action: TrustMVPAction, thread: ThreadRow) -> Bool {
        guard thread.accountId.isEmpty == false else { return false }
        Task {
            await composition.trustActionStore.requestAction(TrustActionRequest(
                action: action,
                target: TrustActionTarget(
                    accountId: thread.accountId,
                    threadId: thread.id,
                    subject: thread.subject
                )
            ))
        }
        return true
    }

    func showToast(_ message: String, undo: ToastState.UndoAction?, kind: ToastState.Kind = .success) {
        let toast = ToastState(message: message, undoAction: undo, kind: kind)
        // Setting toastMessage cancels the previous dismiss task via didSet
        composition.toastMessage = toast
        composition.toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            if composition.toastMessage?.id == toast.id {
                composition.toastMessage = nil
            }
        }
    }

    func showMutationError(_ error: any Error, fallback: String) {
        let message = (error as? MailMutationError)?.localizedDescription
            ?? (error as? LocalizedError)?.errorDescription
            ?? fallback
        showToast(message, undo: nil, kind: .error)
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
                showMutationError(error, fallback: "Undo failed")
            }
        }
    }

    @ViewBuilder
    func toastBar(_ toast: ToastState) -> some View {
        HStack(spacing: RBSpace.s2) {
            RBToast(toast.message, systemImage: toast.kind.systemImage, tint: toast.kind.tint)
            if let action = toast.undoAction {
                Button("Undo") {
                    handleUndo(action)
                }
                .buttonStyle(.rbGhost)
            }
        }
    }

}
