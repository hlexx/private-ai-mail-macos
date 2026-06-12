import DesignSystem
import Foundation
import InboxFeature
import SwiftUI
import ThreadFeature

// MARK: - Thread Navigation (J/K)

extension MainScene {

    enum ThreadNavDirection { case newer, older }

    func navigateThread(direction: ThreadNavDirection) {
        let ordered = inboxStore.threads
        guard !ordered.isEmpty else { return }

        guard let active = inboxStore.selectedThreadID,
              let idx = ordered.firstIndex(where: { $0.id == active }) else {
            inboxStore.selectedThreadID = ordered.first?.id
            return
        }

        let nextIdx: Int
        switch direction {
        case .older: nextIdx = (idx + 1) % ordered.count
        case .newer: nextIdx = (idx - 1 + ordered.count) % ordered.count
        }

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
}

// MARK: - Space: Page Down / Next Unread

extension MainScene {

    func pageDownOrNextUnread() {
        let messages = threadStore.messages
        if let proxy = threadScrollProxy, !messages.isEmpty, !threadScrolledToBottom {
            if scrollToNextMessage(messages, proxy: proxy) {
                return
            }
        }

        selectNextUnreadThread()
    }

    private func scrollToNextMessage(
        _ messages: [MessageRow],
        proxy: ScrollViewProxy
    ) -> Bool {
        let nextIndex = lastScrolledMessageIndex + 1
        if nextIndex < messages.count {
            lastScrolledMessageIndex = nextIndex
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(messages[nextIndex].id, anchor: .top)
            }
            return true
        }

        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(ThreadViewAnchor.composer, anchor: .top)
        }
        threadScrolledToBottom = true
        return true
    }

    private func selectNextUnreadThread() {
        let ordered = inboxStore.threads
        guard let active = inboxStore.selectedThreadID,
              let idx = ordered.firstIndex(where: { $0.id == active }) else { return }

        let nextUnread = ordered[(idx + 1)...].first(where: { $0.hasUnread })
            ?? ordered[..<idx].first(where: { $0.hasUnread })

        if let nextUnread {
            inboxStore.selectedThreadID = nextUnread.id
        } else {
            showToast("No more unread mail", undo: nil)
        }
    }

    func jumpToFolder(_ target: SidebarSelection) {
        sidebarSelection = target
        folderJumpPulse = target
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            folderJumpPulse = nil
        }
    }
}

// MARK: - Theme

extension MainScene {

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
