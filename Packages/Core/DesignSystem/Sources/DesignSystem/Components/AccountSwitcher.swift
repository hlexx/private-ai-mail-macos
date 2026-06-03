import SwiftUI

/// Pill with a color-dot + label + chevron, tappable to cycle accounts.
public struct AccountSwitcher: View {
    public let dotColor: Color
    public let label: String
    public let isEnabled: Bool
    public let onCycle: () -> Void

    @State private var isHovered = false

    public init(dotColor: Color, label: String, onCycle: @escaping () -> Void) {
        self.init(dotColor: dotColor, label: label, isEnabled: true, onCycle: onCycle)
    }

    public init(dotColor: Color, label: String, isEnabled: Bool = true, onCycle: @escaping () -> Void) {
        self.dotColor = dotColor
        self.label = label
        self.isEnabled = isEnabled
        self.onCycle = onCycle
    }

    public var body: some View {
        Button(action: onCycle) {
            let shape = Capsule()

            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.rbGeist(12))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.rbFg3 : Color.rbFg4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: RBControlMetrics.compactHitTarget)
            .background(backgroundColor)
            .overlay(
                shape.strokeBorder(Color.rbStroke1, lineWidth: 1)
            )
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = isEnabled && $0 }
        .accessibilityLabel(label)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { isHovered = false }
        }
    }

    private var labelColor: Color {
        if !isEnabled { return .rbFg4 }
        return isHovered ? .rbFg1 : .rbFg2
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .rbBgElev1 }
        return isHovered ? .rbBgElev2 : .rbBgElev1
    }
}

#if DEBUG
#Preview("Account Switcher") {
    AccountSwitcher(dotColor: .rbCobalt500, label: "alex@studio.eu") {}
        .padding()
        .background(Color.rbBgCanvas)
        .preferredColorScheme(.dark)
}
#endif
