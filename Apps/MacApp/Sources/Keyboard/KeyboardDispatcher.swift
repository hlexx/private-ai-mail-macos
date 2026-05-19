import AppKit
import InboxFeature
import SwiftUI

/// Dispatches keyboard shortcut actions to the appropriate handlers.
/// Centralises the mapping from `ActionKey` to concrete mutations so
/// `MainScene` doesn't need per-shortcut wiring.
@MainActor @Observable
final class KeyboardDispatcher {

    var isTextInputFocused: Bool = false
    var showKeyboardHelp: Bool = false

    /// Set by MainScene so the dispatcher can call mutation methods.
    var actionHandler: ((ActionKey) -> Void)?

    // MARK: - Dispatch

    func handle(_ key: ActionKey) {
        actionHandler?(key)
    }

    // MARK: - Bare-key lookup

    /// Returns the `ActionKey` for a bare-key (no modifier) NSEvent,
    /// or nil if the event doesn't match any spec or should be ignored
    /// because a text field is focused.
    func bareKeyAction(for event: NSEvent) -> ActionKey? {
        guard event.type == .keyDown else { return nil }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        // Two-pass matching:
        // Pass 1: Use event.characters (includes shift effect, e.g. "?" from Shift+/).
        //         Strip .shift from flags since it was consumed to produce the character.
        // Pass 2: Use event.charactersIgnoringModifiers (e.g. "i" for Shift+I).
        //         Keep .shift in flags so specs with .shift modifier match correctly.

        if let produced = event.characters?.first {
            let flagsShiftStripped = flags.subtracting(.shift)
            for spec in ShortcutSpec.all where spec.requiresInputBlur {
                if spec.key.character == produced && flagsMatch(flagsShiftStripped, spec: spec) {
                    return spec.actionKey
                }
            }
        }

        if let base = event.charactersIgnoringModifiers?.first {
            for spec in ShortcutSpec.all where spec.requiresInputBlur {
                if spec.key.character == base && flagsMatch(flags, spec: spec) {
                    return spec.actionKey
                }
            }
        }

        return nil
    }

    private func flagsMatch(_ eventFlags: NSEvent.ModifierFlags, spec: ShortcutSpec) -> Bool {
        var expected: NSEvent.ModifierFlags = []
        if spec.modifiers.contains(.command) { expected.insert(.command) }
        if spec.modifiers.contains(.option) { expected.insert(.option) }
        if spec.modifiers.contains(.control) { expected.insert(.control) }
        if spec.modifiers.contains(.shift) { expected.insert(.shift) }
        return eventFlags == expected
    }
}
