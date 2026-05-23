import AIKit
import ComposeFeature
import DesignSystem
import GRDB
import InboxFeature
import MailSync
import Persistence
import SwiftUI
import ThreadFeature
import TranslationFeature

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
        return NodeLanguageDetector.detect(text)?.bcp47
    }

    func detectReplyLanguage() -> String? {
        guard let text = lastIncomingText(), !text.isEmpty else {
            return preferredLanguage.isEmpty ? nil : preferredLanguage
        }
        guard let detected = NodeLanguageDetector.detect(text),
              detected.confidence >= 0.5 else {
            return preferredLanguage.isEmpty ? nil : preferredLanguage
        }
        return detected.bcp47
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
        vm.accounts = accounts.map { AccountInfo(id: $0.id, email: $0.email, displayName: $0.displayName) }
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
        vm.accounts = accounts.map { AccountInfo(id: $0.id, email: $0.email, displayName: $0.displayName) }
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
        Task {
            do {
                try await composition.mailMutator.archive(threadId, accountId: accountId)
                inboxStore.selectedThreadID = nil
                showToast("Archived", undo: .unarchive(threadId: threadId, accountId: accountId))
            } catch {
                showToast(mailboxActionFailureMessage("Archive", error: error), undo: nil)
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
                showToast(mailboxActionFailureMessage("Star", error: error), undo: nil)
            }
        }
    }

    func markReadSelectedThread() {
        guard let threadId = inboxStore.selectedThreadID,
              let thread = inboxStore.threads.first(where: { $0.id == threadId }) else { return }
        let accountId = thread.accountId
        Task {
            do {
                try await composition.mailMutator.markRead(threadId, accountId: accountId, read: true)
                showToast("Marked read", undo: nil)
            } catch {
                showToast(mailboxActionFailureMessage("Mark read", error: error), undo: nil)
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
                showToast(mailboxActionFailureMessage("Trash", error: error), undo: nil)
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

    func previewAttachment(_ request: AttachmentPreviewRequest) {
        switch composition.attachmentPreviewService.preview(request) {
        case .opened:
            break
        case .missingLocalFile:
            showToast("Attachment is not saved locally yet.", undo: nil)
        case .failedToOpen:
            showToast("Attachment preview could not be opened.", undo: nil)
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
                showToast(mailboxActionFailureMessage("Undo", error: error), undo: nil)
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

    func mailboxActionFailureMessage(_ action: String, error: any Error) -> String {
        guard let mutationError = error as? MailMutationError else {
            return "\(action) failed. Gmail did not accept the change."
        }
        switch mutationError {
        case .missingCredential:
            return "\(action) failed. Reconnect this Gmail account."
        case .providerRejected:
            return "\(action) failed. Gmail rejected the request."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "\(action) paused. Gmail rate limit hit; retry in \(Int(retryAfter))s."
            }
            return "\(action) paused. Gmail rate limit hit; retry later."
        case .offline:
            return "\(action) failed. You appear to be offline."
        case .degradedSync:
            return "\(action) failed. Gmail sync is degraded; local state was restored."
        case .providerFailure:
            return "\(action) failed. Gmail did not accept the change."
        }
    }

    // MARK: - Thread Navigation (J/K)

    enum ThreadNavDirection { case newer, older }

    func navigateThread(direction: ThreadNavDirection) {
        let ordered = inboxStore.threads
        guard !ordered.isEmpty else { return }

        guard let active = inboxStore.selectedThreadID,
              let idx = ordered.firstIndex(where: { $0.id == active }) else {
            // No selection — select the first thread
            inboxStore.selectedThreadID = ordered.first?.id
            return
        }

        let nextIdx: Int
        switch direction {
        case .older: nextIdx = (idx + 1) % ordered.count
        case .newer: nextIdx = (idx - 1 + ordered.count) % ordered.count
        }

        // Wrap-around feedback
        let didWrap = (direction == .older && idx == ordered.count - 1 && nextIdx == 0) ||
                      (direction == .newer && idx == 0 && nextIdx == ordered.count - 1)
        if didWrap {
            threadListWrapPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                threadListWrapPulse = false
            }
        }

        inboxStore.selectedThreadID = ordered[nextIdx].id
    }

    // MARK: - Space: Page Down / Next Unread

    func pageDownOrNextUnread() {
        // Scroll through messages one-by-one, then advance to next unread thread.
        let messages = threadStore.messages
        if let proxy = threadScrollProxy, !messages.isEmpty, !threadScrolledToBottom {
            let nextIndex = lastScrolledMessageIndex + 1
            if nextIndex < messages.count {
                // Scroll to the next message in the thread
                lastScrolledMessageIndex = nextIndex
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(messages[nextIndex].id, anchor: .top)
                }
                return
            } else {
                // Scrolled past last message — scroll to composer anchor
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(ThreadViewAnchor.composer, anchor: .top)
                }
                threadScrolledToBottom = true
                return
            }
        }

        // At bottom or no scroll proxy — find next unread thread
        let ordered = inboxStore.threads
        guard let active = inboxStore.selectedThreadID,
              let idx = ordered.firstIndex(where: { $0.id == active }) else { return }

        let afterCurrent = ordered[(idx + 1)...]
        let beforeCurrent = ordered[..<idx]
        let nextUnread = afterCurrent.first(where: { $0.hasUnread })
            ?? beforeCurrent.first(where: { $0.hasUnread })

        if let next = nextUnread {
            inboxStore.selectedThreadID = next.id
        } else {
            showToast("No more unread mail", undo: nil)
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
