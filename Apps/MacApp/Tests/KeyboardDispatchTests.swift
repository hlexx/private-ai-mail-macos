import SwiftUI
import Testing

@testable import PrivateAIMail

@Suite("KeyboardDispatch")
struct KeyboardDispatchTests {

    @MainActor
    @Test("Bare key R dispatches .reply when text input not focused")
    func bareKeyReplyWhenNotFocused() {
        let dispatcher = KeyboardDispatcher()
        var receivedAction: ActionKey?
        dispatcher.actionHandler = { action in receivedAction = action }
        dispatcher.isTextInputFocused = false

        // Simulate a bare "r" key event
        let event = makeKeyEvent(characters: "r", modifierFlags: [])
        let action = dispatcher.bareKeyAction(for: event)

        #expect(action == .reply)

        // Verify dispatch works
        if let action {
            dispatcher.handle(action)
        }
        #expect(receivedAction == .reply)
    }

    @MainActor
    @Test("Bare key R returns action even when isTextInputFocused is true (monitor checks separately)")
    func bareKeyReplyActionLookup() {
        // bareKeyAction only looks up the mapping; the monitor layer
        // checks isTextInputFocused before calling it. This test
        // verifies the lookup itself is independent.
        let dispatcher = KeyboardDispatcher()
        dispatcher.isTextInputFocused = true

        let event = makeKeyEvent(characters: "r", modifierFlags: [])
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .reply)
    }

    @MainActor
    @Test("Bare key E dispatches .archive")
    func bareKeyArchive() {
        let dispatcher = KeyboardDispatcher()
        let event = makeKeyEvent(characters: "e", modifierFlags: [])
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .archive)
    }

    @MainActor
    @Test("Bare key S dispatches .star")
    func bareKeyStar() {
        let dispatcher = KeyboardDispatcher()
        let event = makeKeyEvent(characters: "s", modifierFlags: [])
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .star)
    }

    @MainActor
    @Test("Bare key J dispatches .threadNewer")
    func bareKeyJ() {
        let dispatcher = KeyboardDispatcher()
        let event = makeKeyEvent(characters: "j", modifierFlags: [])
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .threadNewer)
    }

    @MainActor
    @Test("Bare key K dispatches .threadOlder")
    func bareKeyK() {
        let dispatcher = KeyboardDispatcher()
        let event = makeKeyEvent(characters: "k", modifierFlags: [])
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .threadOlder)
    }

    @MainActor
    @Test("Bare key ? dispatches .showHelp")
    func bareKeyHelp() {
        let dispatcher = KeyboardDispatcher()
        let event = makeKeyEvent(characters: "?", modifierFlags: .shift)
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == .showHelp)
    }

    @MainActor
    @Test("Unrecognized bare key returns nil")
    func unrecognizedKey() {
        let dispatcher = KeyboardDispatcher()
        let event = makeKeyEvent(characters: "z", modifierFlags: [])
        let action = dispatcher.bareKeyAction(for: event)
        #expect(action == nil)
    }

    @MainActor
    @Test("Modified key (⌘R) does not match as bare key")
    func modifiedKeyNotBare() {
        let dispatcher = KeyboardDispatcher()
        let event = makeKeyEvent(characters: "r", modifierFlags: .command)
        let action = dispatcher.bareKeyAction(for: event)
        // ⌘R is a modified shortcut, not a bare key — should not match bare specs
        #expect(action == nil)
    }

    @MainActor
    @Test("Handle dispatches to action handler")
    func handleDispatch() {
        let dispatcher = KeyboardDispatcher()
        var actions: [ActionKey] = []
        dispatcher.actionHandler = { actions.append($0) }

        dispatcher.handle(.archive)
        dispatcher.handle(.star)
        dispatcher.handle(.reply)

        #expect(actions == [.archive, .star, .reply])
    }

    // MARK: - Helpers

    private func makeKeyEvent(characters: String, modifierFlags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
    }
}
