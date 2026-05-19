import AppKit
import SwiftUI

// MARK: - View Modifier

extension View {
    func mailKeyboardShortcuts(dispatcher: KeyboardDispatcher) -> some View {
        self
            .modifier(ModifiedKeyShortcutsModifier(dispatcher: dispatcher))
            .background(BareKeyMonitor(dispatcher: dispatcher))
    }
}

// MARK: - Modified-key shortcuts (⌘R, ⌘⇧R, etc.)

/// Attaches invisible buttons for every `ShortcutSpec` that has modifier keys,
/// reusing the existing hidden-button pattern from MainScene.
private struct ModifiedKeyShortcutsModifier: ViewModifier {
    let dispatcher: KeyboardDispatcher

    func body(content: Content) -> some View {
        content.background {
            ForEach(modifiedSpecs) { spec in
                Button("") { dispatcher.handle(spec.actionKey) }
                    .keyboardShortcut(spec.key, modifiers: spec.modifiers)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Specs handled by the CommandMenu in PrivateAIMailApp (already have
    /// menu-level `.keyboardShortcut` registrations).
    private static let menuHandledActions: Set<ActionKey> = [
        .reply, .replyAll, .forward, .trash, .refresh, .showHelp, .newCompose,
    ]

    private var modifiedSpecs: [ShortcutSpec] {
        ShortcutSpec.all.filter {
            !$0.modifiers.isEmpty
            && !$0.requiresInputBlur
            && $0.scope != .compose
            && !Self.menuHandledActions.contains($0.actionKey)
        }
    }
}

// MARK: - Bare-key monitor (R, E, S, J, K, etc.)

/// An invisible `NSViewRepresentable` that installs an `NSEvent` local
/// monitor for `.keyDown` events. When a bare-key shortcut fires, it
/// checks whether the first responder is a text input; if so, the
/// event passes through for normal typing. Otherwise, the matching
/// `ActionKey` is dispatched and the event is consumed.
private struct BareKeyMonitor: NSViewRepresentable {
    let dispatcher: KeyboardDispatcher

    func makeNSView(context: Context) -> NSView {
        let view = BareKeyMonitorView()
        view.dispatcher = dispatcher
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? BareKeyMonitorView)?.dispatcher = dispatcher
    }
}

private final class BareKeyMonitorView: NSView {
    var dispatcher: KeyboardDispatcher?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event) ?? event
            }
        } else if window == nil {
            removeMonitor()
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    deinit {
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard let dispatcher else { return event }

        // If a text field or text editor is the first responder, let the
        // event pass through so the user can type normally.
        // Check both NSEvent-level (authoritative) and Swift-level signal.
        if isTextInputFirstResponder() || dispatcher.isTextInputFocused {
            return event
        }

        guard let actionKey = dispatcher.bareKeyAction(for: event) else {
            return event
        }

        Task { @MainActor in
            dispatcher.handle(actionKey)
        }
        return nil // consume the event
    }

    private func isTextInputFirstResponder() -> Bool {
        guard let responder = window?.firstResponder else { return false }
        // NSTextView is used by SwiftUI's TextEditor and TextField under the hood.
        // When an NSTextField begins editing, its field editor (NSTextView) becomes
        // first responder, so checking NSTextView alone is sufficient.
        return responder is NSTextView
    }
}
