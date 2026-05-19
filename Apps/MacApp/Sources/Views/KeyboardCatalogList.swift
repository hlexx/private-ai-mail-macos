import DesignSystem
import SwiftUI

/// Shared grouped-list rendering of keyboard shortcuts, used by both
/// the `?` help overlay and the Settings → Keyboard tab.
struct KeyboardCatalogList: View {

    private var visibleSpecs: [ShortcutSpec] {
        ShortcutSpec.all.filter { !$0.deprecated }
    }

    private var groupedSpecs: [(section: KeyboardSection, specs: [ShortcutSpec])] {
        KeyboardSection.allCases.compactMap { section in
            let specs = visibleSpecs.filter { $0.section == section }
            return specs.isEmpty ? nil : (section, specs)
        }
    }

    private var deduplicatedGroups: [(section: KeyboardSection, rows: [ShortcutRow])] {
        groupedSpecs.map { section, specs in
            var seen = Set<String>()
            var rows: [ShortcutRow] = []
            for spec in specs {
                let key = "\(section.rawValue).\(spec.actionKey.rawValue)"
                if seen.contains(key) {
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
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(deduplicatedGroups.enumerated()), id: \.offset) { _, group in
                sectionView(title: group.section.title, rows: group.rows)
            }
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

struct ShortcutRow: Identifiable {
    let label: String
    let actionKey: ActionKey
    var keyCombos: [String]

    var id: String { actionKey.rawValue }
}
