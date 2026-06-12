import ComposeFeature
import Foundation
import MailDomain
import SwiftUI
import ThreadFeature

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

    func prepareNewCompose() {
        let vm = composition.composeViewModel
        vm.reset()
        vm.accounts = accounts.map {
            AccountInfo(
                id: $0.id,
                email: $0.email,
                displayName: $0.displayName,
                provider: MailProviderIdentifier(rawValue: $0.provider)
            )
        }
        if let activeID = composition.activeAccountID ?? accounts.first?.id {
            vm.selectedAccountID = activeID
            vm.selectedAccountEmail = accounts.first(where: { $0.id == activeID })?.email
        }
    }

    func prefillComposeForReply() {
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

        let inReplyToID = lastMessage.messageIdHeader ?? lastMessage.id
        let referencesChain = threadStore.messages.compactMap(\.messageIdHeader)

        let threadAccountId = inboxStore.threads.first(where: { $0.id == lastMessage.threadId })?.accountId
        let replyAccountId = threadAccountId ?? composition.activeAccountID
        let replyAccountEmail = accounts.first(where: { $0.id == replyAccountId })?.email

        vm.prefillReply(
            fromAddr: replyToAddr,
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

        // Compare bare emails so "Name <x@y>" matches "x@y".
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
        var results: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false
        for ch in raw {
            switch ch {
            case "\"":
                inQuotes.toggle()
                current.append(ch)
            case "<" where !inQuotes:
                inAngle = true
                current.append(ch)
            case ">" where !inQuotes:
                inAngle = false
                current.append(ch)
            case "," where !inQuotes && !inAngle:
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { results.append(trimmed) }
                current = ""
            default:
                current.append(ch)
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
}
