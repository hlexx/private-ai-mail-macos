import DesignSystem
import SwiftUI

struct InlineComposerLanguageChevron: View {
    let action: () -> Void

    var body: some View {
        let title = String(
            localized: "composer.languagePicker.tooltip",
            defaultValue: "Change reply language"
        )

        Button(action: action) {
            Label(title, systemImage: "chevron.down")
                .labelStyle(.iconOnly)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.rbFg3)
                .frame(
                    width: RBControlMetrics.compactHitTarget,
                    height: RBControlMetrics.compactHitTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}

struct InlineComposerLanguagePickerRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .font(.rbGeist(13))
                    .foregroundStyle(Color.rbFg1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.rbAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: RBControlMetrics.compactHitTarget, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}
