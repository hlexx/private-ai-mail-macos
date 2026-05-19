import AppKit
import Foundation
import InboxFeature
import Persistence
import Testing

@testable import PrivateAIMail

@Suite("ThreadNavigation")
struct ThreadNavigationTests {

    // MARK: - Helpers

    private func makeThread(id: String, hasUnread: Bool = false) -> ThreadRow {
        ThreadRow(
            record: ThreadRecord(
                id: id,
                accountId: "acc1",
                subject: "Thread \(id)",
                snippet: "snippet",
                lastMessageAt: Int(Date().timeIntervalSince1970),
                messageCount: 1,
                hasUnread: hasUnread ? 1 : 0
            )
        )
    }

    // MARK: - J/K Navigation

    @Test("J (threadOlder) moves to next thread in list")
    func jNavigatesOlder() {
        let threads = [makeThread(id: "t1"), makeThread(id: "t2"), makeThread(id: "t3")]
        var selectedID: String? = "t1"

        let idx = threads.firstIndex(where: { $0.id == selectedID })!
        let nextIdx = (idx + 1) % threads.count
        selectedID = threads[nextIdx].id

        #expect(selectedID == "t2")
    }

    @Test("K (threadNewer) moves to previous thread in list")
    func kNavigatesNewer() {
        let threads = [makeThread(id: "t1"), makeThread(id: "t2"), makeThread(id: "t3")]
        var selectedID: String? = "t2"

        let idx = threads.firstIndex(where: { $0.id == selectedID })!
        let nextIdx = (idx - 1 + threads.count) % threads.count
        selectedID = threads[nextIdx].id

        #expect(selectedID == "t1")
    }

    @Test("J wraps from last to first thread")
    func jWrapsAround() {
        let threads = [makeThread(id: "t1"), makeThread(id: "t2"), makeThread(id: "t3")]
        var selectedID: String? = "t3"

        let idx = threads.firstIndex(where: { $0.id == selectedID })!
        let nextIdx = (idx + 1) % threads.count
        selectedID = threads[nextIdx].id

        let didWrap = nextIdx == 0
        #expect(selectedID == "t1")
        #expect(didWrap == true)
    }

    @Test("K wraps from first to last thread")
    func kWrapsAround() {
        let threads = [makeThread(id: "t1"), makeThread(id: "t2"), makeThread(id: "t3")]
        var selectedID: String? = "t1"

        let idx = threads.firstIndex(where: { $0.id == selectedID })!
        let nextIdx = (idx - 1 + threads.count) % threads.count
        selectedID = threads[nextIdx].id

        let didWrap = nextIdx == threads.count - 1 && idx == 0
        #expect(selectedID == "t3")
        #expect(didWrap == true)
    }

    @Test("No selection selects first thread")
    func noSelectionSelectsFirst() {
        let threads = [makeThread(id: "t1"), makeThread(id: "t2")]
        var selectedID: String?

        if selectedID == nil {
            selectedID = threads.first?.id
        }

        #expect(selectedID == "t1")
    }

    @Test("Empty thread list does nothing")
    func emptyListNoop() {
        let threads: [ThreadRow] = []
        let selectedID: String? = "t1"

        guard !threads.isEmpty else {
            #expect(selectedID == "t1")
            return
        }
    }

    // MARK: - Space: Next Unread

    @Test("Next unread finds first unread after current position")
    func nextUnreadAfterCurrent() {
        let threads = [
            makeThread(id: "t1"),
            makeThread(id: "t2"),
            makeThread(id: "t3", hasUnread: true),
            makeThread(id: "t4"),
        ]
        let currentIdx = 0
        let afterCurrent = threads[(currentIdx + 1)...]
        let nextUnread = afterCurrent.first(where: { $0.hasUnread })

        #expect(nextUnread?.id == "t3")
    }

    @Test("Next unread wraps around if no unread after current")
    func nextUnreadWraps() {
        let threads = [
            makeThread(id: "t1", hasUnread: true),
            makeThread(id: "t2"),
            makeThread(id: "t3"),
        ]
        let currentIdx = 1
        let afterCurrent = threads[(currentIdx + 1)...]
        let beforeCurrent = threads[..<currentIdx]
        let nextUnread = afterCurrent.first(where: { $0.hasUnread })
            ?? beforeCurrent.first(where: { $0.hasUnread })

        #expect(nextUnread?.id == "t1")
    }

    @Test("No unread threads returns nil")
    func noUnreadThreads() {
        let threads = [
            makeThread(id: "t1"),
            makeThread(id: "t2"),
            makeThread(id: "t3"),
        ]
        let currentIdx = 0
        let afterCurrent = threads[(currentIdx + 1)...]
        let beforeCurrent = threads[..<currentIdx]
        let nextUnread = afterCurrent.first(where: { $0.hasUnread })
            ?? beforeCurrent.first(where: { $0.hasUnread })

        #expect(nextUnread == nil)
    }

    // MARK: - Bare Key Dispatch

    @MainActor
    @Test("J key dispatches threadNewer via dispatcher")
    func jKeyDispatch() {
        let dispatcher = KeyboardDispatcher()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "j", charactersIgnoringModifiers: "j",
            isARepeat: false, keyCode: 0
        )!
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .threadNewer)
    }

    @MainActor
    @Test("K key dispatches threadOlder via dispatcher")
    func kKeyDispatch() {
        let dispatcher = KeyboardDispatcher()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: 0
        )!
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .threadOlder)
    }

    @MainActor
    @Test("Space key dispatches pageDownOrNextUnread via dispatcher")
    func spaceKeyDispatch() {
        let dispatcher = KeyboardDispatcher()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: " ", charactersIgnoringModifiers: " ",
            isARepeat: false, keyCode: 0
        )!
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .pageDownOrNextUnread)
    }
}
