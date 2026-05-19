import DesignSystem
import SwiftUI

struct KeyboardHelpOverlay: View {

    @Binding var isPresented: Bool

    private var visibleSpecs: [ShortcutSpec] {
        ShortcutSpec.all.filter { !$0.deprecated }
    }

    private var groupedSpecs: [(section: KeyboardSection, specs: [ShortcutSpec])] {
        KeyboardSection.allCases.compactMap { section in
            let specs = visibleSpecs.filter { $0.section == section }
            return specs.isEmpty ? nil : (section, specs)
        }
    }

    // De-duplicate specs that share the same actionKey within a section
    // (e.g. Cmd+R and bare R both map to Reply). Show the primary (first)
    // label with all its key combos.
    private var deduplicatedGroups: [(section: KeyboardSection, rows: [ShortcutRow])] {
        groupedSpecs.map { section, specs in
            var seen = Set<String>()
            var rows: [ShortcutRow] = []
            for spec in specs {
                let key = "\(section.rawValue).\(spec.actionKey.rawValue)"
                if seen.contains(key) {
                    // Append this key combo to the existing row
                    if let idx = rows.firstIndex(where: { $0.actionKey == spec.actionKey }) {
                        rows[idx].keyCombos.append(spec.displayKeyCombo)
                    }
                } else {
                    seen.insert(key)
                    rows.append(ShortcutRow(
                        label: spec.label,
                        actionKey: spec.actionKey,
                        keyCombos: [spec.displayKeyCombo]
                    ))
                }
            }
            return (section, rows)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                    .foregroundStyle(Color.rbFg1)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.rbFg3)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .background(Color.rbStroke2)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(deduplicatedGroups.enumerated()), id: \.offset) { _, group in
                        sectionView(title: group.section.title, rows: group.rows)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 480, height: 520)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.rbStroke2, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    @ViewBuilder
    private func sectionView(title: String, rows: [ShortcutRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.rbFg3)
                .padding(.bottom, 2)

            ForEach(rows) { row in
                HStack {
                    HStack(spacing: 6) {
                        ForEach(Array(row.keyCombos.enumerated()), id: \.offset) { idx, combo in
                            if idx > 0 {
                                Text("/")
                                    .font(.caption)
                                    .foregroundStyle(Color.rbFg4)
                            }
                            Text(combo)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color.rbFg1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.rbBgElev2)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .frame(minWidth: 160, alignment: .trailing)

                    Text(row.label)
                        .foregroundStyle(Color.rbFg2)
                        .padding(.leading, 12)

                    Spacer()
                }
            }
        }
    }
}

// MARK: - Row Model

private struct ShortcutRow: Identifiable {
    let label: String
    let actionKey: ActionKey
    var keyCombos: [String]

    var id: String { actionKey.rawValue }
}

// MARK: - Display Key Combo

extension ShortcutSpec {
    var displayKeyCombo: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option) { parts.append("\u{2325}") }
        if modifiers.contains(.shift) { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }

        let keyStr = displayKeyName
        parts.append(keyStr)
        return parts.joined()
    }

    private var displayKeyName: String {
        let char = key.character
        switch char {
        case "\r", "\n": return "\u{21A9}" // Return
        case " ": return "Space"
        case "\u{7F}", "\u{08}": return "\u{232B}" // Delete
        default: break
        }

        // F-keys: NSF5FunctionKey etc. are in the Unicode private use area
        let scalar = char.unicodeScalars.first?.value ?? 0
        if scalar == UInt32(NSF5FunctionKey) { return "F5" }

        // Regular character — uppercase for display
        return String(char).uppercased()
    }
}
