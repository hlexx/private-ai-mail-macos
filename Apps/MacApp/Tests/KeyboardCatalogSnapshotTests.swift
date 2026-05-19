import SwiftUI
import Testing

@testable import PrivateAIMail

@Suite("KeyboardCatalogSnapshot")
struct KeyboardCatalogSnapshotTests {

    /// Renders the catalog as a human-readable text block grouped by section.
    /// If you change shortcuts, update the expected baseline below.
    @Test("Catalog snapshot matches baseline")
    func catalogSnapshot() {
        let rendered = renderCatalog()
        #expect(rendered == Self.baseline, """
        Keyboard catalog snapshot mismatch.
        If you intentionally changed shortcuts, update the baseline in this test.

        Got:
        \(rendered)
        """)
    }

    // MARK: - Helpers

    private func renderCatalog() -> String {
        var lines: [String] = []
        for section in KeyboardSection.allCases {
            let specs = ShortcutSpec.all.filter { $0.section == section }
            guard !specs.isEmpty else { continue }
            lines.append("[\(section.title)]")
            for spec in specs {
                let combo = formatCombo(spec)
                let suffix = spec.deprecated ? " (deprecated)" : ""
                lines.append("  \(combo) — \(spec.label)\(suffix)")
            }
            lines.append("")
        }
        // Remove trailing empty line
        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private func formatCombo(_ spec: ShortcutSpec) -> String {
        var parts: [String] = []
        if spec.modifiers.contains(.command) { parts.append("⌘") }
        if spec.modifiers.contains(.option) { parts.append("⌥") }
        if spec.modifiers.contains(.control) { parts.append("⌃") }
        if spec.modifiers.contains(.shift) { parts.append("⇧") }

        let keyStr = describeKey(spec.key)
        parts.append(keyStr)
        return parts.joined()
    }

    private func describeKey(_ key: KeyEquivalent) -> String {
        let char = key.character
        switch char {
        case "\r": return "⏎"
        case " ": return "Space"
        case "\u{7F}": return "⌫"
        default:
            let scalar = char.unicodeScalars.first!
            if scalar.value == UInt32(0xF708) { return "F5" }
            return String(char).uppercased()
        }
    }

    // MARK: - Baseline

    static let baseline = """
    [Mail]
      ⌘R — Reply
      R — Reply
      ⌘⇧R — Reply All
      A — Reply All
      ⌘⌥F — Forward
      F — Forward
      E — Archive
      ⌃E — Archive (legacy) (deprecated)
      S — Star / Unstar
      ⌃S — Star (legacy) (deprecated)
      # — Trash
      ⌘⌫ — Trash
      ⇧I — Mark Read
      ⇧U — Mark Unread

    [Navigation]
      J — Older Thread
      K — Newer Thread
      Space — Page Down / Next Unread
      ⌘1 — Go to Inbox
      ⌘2 — Go to Starred
      ⌘3 — Go to Sent
      ⌘4 — Go to Archive
      ⌘5 — All Accounts
      ⌘L — Focus Search

    [Compose]
      ⌘N — New Message
      ⌘⏎ — Send

    [View]
      F5 — Refresh
      ⌘⇧L — Refresh
      ⌘K — Action Sheet
      ? — Keyboard Shortcuts
    """
}
