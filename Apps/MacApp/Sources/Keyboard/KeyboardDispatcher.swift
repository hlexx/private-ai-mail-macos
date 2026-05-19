import AppKit
import InboxFeature
import SwiftUI

/// Dispatches keyboard shortcut actions to the appropriate handlers.
/// Centralises the mapping from `ActionKey` to concrete mutations so
/// `MainScene` doesn't need per-shortcut wiring.
@MainActor @Observable
final class KeyboardDispatcher {

    var isTextInputFocused: Bool = false

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

        let chars = event.charactersIgnoringModifiers ?? ""
        guard let char = chars.first else { return nil }

        // Only match specs that require input blur (bare-key Gmail-style)
        // AND have no modifiers (or only shift for things like ? # I U).
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        for spec in ShortcutSpec.all where spec.requiresInputBlur {
            let specChar = spec.key.character
            if specChar == char && flagsMatch(flags, spec: spec) {
                return spec.actionKey
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
