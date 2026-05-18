import AIKit
import DesignSystem
import GRDB
import InboxFeature
import Persistence
import SwiftUI
import ThreadFeature

// MARK: - Translation Helpers

extension MainScene {

    func lastIncomingText() -> String? {
        if let lastIncoming = threadStore.messages.last(where: { !$0.isSentByMe }) {
            return lastIncoming.bestPlainText
        }
        return threadStore.messages.last?.bestPlainText
    }

    func detectThreadLanguage() -> String? {
        guard let text = lastIncomingText() else { return nil }
        return translationStore.detect(text: text)
    }

    func detectReplyLanguage() -> String? {
        guard let text = lastIncomingText(), !text.isEmpty else {
            return preferredLanguage.isEmpty ? nil : preferredLanguage
        }
        guard let result = translationStore.detectWithConfidence(text: text),
              result.confidence >= 0.5 else {
            return preferredLanguage.isEmpty ? nil : preferredLanguage
        }
        return result.language
    }
}

// MARK: - Mutation & Toast Helpers

extension MainScene {

    func draftReply() {
        guard let threadID = inboxStore.selectedThreadID else { return }
        let accountId = inboxStore.threads.first(where: { $0.id == threadID })?.accountId
        withAnimation {
            threadScrollProxy?.scrollTo(ThreadViewAnchor.composer, anchor: .top)
        }
        let tone = AIReplyTone(rawValue: defaultToneRaw) ?? .warm
        composition.replyStore.generateIfNeeded(
            threadID: threadID,
            accountId: accountId,
            tone: tone,
            replyLanguage: detectReplyLanguage()
        )
    }

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
            if let action = toast.undoAction {
                Button("Undo") {
                    handleUndo(action)
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
