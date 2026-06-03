import ActionsFeature
import ComposeFeature
import DesignSystem
import GRDB
import InboxFeature
import MailDomain
import MailSync
import Persistence
import SwiftUI
import ThreadFeature

// MARK: - Mutation & Toast Helpers

extension MainScene {

    func draftReply(threadID requestedThreadID: String? = nil, accountId requestedAccountID: String? = nil) {
        guard composition.aiModelController.isAIReady else {
            openSettings()
            return
        }
        let threadID = requestedThreadID ?? inboxStore.selectedThreadID
        guard let threadID else { return }
        guard let thread = threadRow(threadID: threadID, accountId: requestedAccountID) else { return }
        if inboxStore.selectedThreadID != threadID {
            inboxStore.selectedThreadID = threadID
        }
        bottomPanelCollapsed = false
        bottomPanelTabRaw = "draft"
        withAnimation {
            threadScrollProxy?.scrollTo(ThreadViewAnchor.composer, anchor: .top)
        }
        draftGenerationRequest = InlineDraftGenerationRequest(threadID: thread.id, accountId: thread.accountId)
    }

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

    func replyAll() {
        guard inboxStore.selectedThreadID != nil else { return }
        prefillComposeForReplyAll()
        composition.showCompose = true
    }

    func forwardThread() {
        guard inboxStore.selectedThreadID != nil else { return }
        prefillComposeForForward()
        composition.showCompose = true
    }

    private func prefillComposeForReplyAll() {
        let vm = composition.composeViewModel
        vm.reset()
        guard let lastMessage = threadStore.messages.last else { return }

        let replyTarget = threadStore.messages.last(where: { !$0.isSentByMe })
        let replyToAddr: String
        if let target = replyTarget {
            replyToAddr = extractEmail(from: target.fromAddr)
        } else {
            replyToAddr = extractEmail(from: lastMessage.toAddr)
        }

        let threadAccountId = inboxStore.threads.first(where: { $0.id == lastMessage.threadId })?.accountId
        let replyAccountId = threadAccountId ?? composition.activeAccountID
        let replyAccountEmail = accounts.first(where: { $0.id == replyAccountId })?.email

        // Collect all To and Cc addresses, then remove the sender (already in To:)
        // and the current user's own address to avoid duplicates.
        // Compare bare emails (extractEmail) so "Name <x@y>" matches "x@y".
        let excludeAddrs = Set([replyToAddr.lowercased(), (replyAccountEmail ?? "").lowercased()]
            .filter { !$0.isEmpty })
        let allTo = parseAddressList(lastMessage.toAddr)
            .filter { !excludeAddrs.contains(extractEmail(from: $0).lowercased()) }
        let allCc = parseAddressList(lastMessage.ccAddr)
            .filter { !excludeAddrs.contains(extractEmail(from: $0).lowercased()) }
        let dedupCc = allTo.joined(separator: ", ")
        let dedupCcExtra = allCc.joined(separator: ", ")

        let inReplyToID = lastMessage.messageIdHeader ?? lastMessage.id
        let referencesChain = threadStore.messages.compactMap(\.messageIdHeader)

        vm.prefillReplyAll(
            fromAddr: replyToAddr,
            allToAddrs: dedupCc,
            allCcAddrs: dedupCcExtra,
            subject: threadStore.subject,
            threadID: lastMessage.threadId,
            lastMessageID: inReplyToID,
            referencesChain: referencesChain
        )
        vm.accounts = accounts.map {
            AccountInfo(
                id: $0.id,
                email: $0.email,
                displayName: $0.displayName,
                provider: MailProviderIdentifier(rawValue: $0.provider)
            )
        }
        if let accountID = replyAccountId {
            vm.selectedAccountID = accountID
            vm.selectedAccountEmail = replyAccountEmail
        }
    }

    private func parseAddressList(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        // Split on commas, respecting quoted strings and angle brackets
        // so that "Doe, John" <john@example.com> stays as one address.
        var results: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false
        for ch in raw {
            switch ch {
            case "\"": inQuotes.toggle(); current.append(ch)
            case "<" where !inQuotes: inAngle = true; current.append(ch)
            case ">" where !inQuotes: inAngle = false; current.append(ch)
            case "," where !inQuotes && !inAngle:
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { results.append(trimmed) }
                current = ""
            default: current.append(ch)
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { results.append(trimmed) }
        return results
    }

    private func prefillComposeForForward() {
        let vm = composition.composeViewModel
        vm.reset()
        guard let lastMessage = threadStore.messages.last else { return }

        let quotedBody = buildForwardQuote(lastMessage)
        let inReplyToID = lastMessage.messageIdHeader ?? lastMessage.id
        let referencesChain = threadStore.messages.compactMap(\.messageIdHeader)

        let threadAccountId = inboxStore.threads.first(where: { $0.id == lastMessage.threadId })?.accountId
        let fwdAccountId = threadAccountId ?? composition.activeAccountID
        let fwdAccountEmail = accounts.first(where: { $0.id == fwdAccountId })?.email

        vm.prefillForward(
            subject: threadStore.subject,
            quotedBody: quotedBody,
            threadID: lastMessage.threadId,
            lastMessageID: inReplyToID,
            referencesChain: referencesChain
        )
        vm.accounts = accounts.map {
            AccountInfo(
                id: $0.id,
                email: $0.email,
                displayName: $0.displayName,
                provider: MailProviderIdentifier(rawValue: $0.provider)
            )
        }
        if let accountID = fwdAccountId {
            vm.selectedAccountID = accountID
            vm.selectedAccountEmail = fwdAccountEmail
        }
    }

    private func buildForwardQuote(_ message: MessageRow) -> String {
        let from = message.fromAddr
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: message.sentAt)
        let body = message.bestPlainText

        return """

        ---------- Forwarded message ----------
        From: \(from)
        Date: \(dateStr)
        Subject: \(threadStore.subject)

        \(body)
        """
    }

    func archiveSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        if requestTrustActionIfSupported(.archiveThread, thread: thread) {
            return
        }
        Task {
            do {
                try await composition.mailMutator.archive(threadId, accountId: accountId)
                inboxStore.selectedThreadID = nil
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
