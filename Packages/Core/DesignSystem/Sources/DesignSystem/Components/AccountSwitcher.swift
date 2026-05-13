import SwiftUI

/// Pill with a color-dot + label + chevron, tappable to cycle accounts.
public struct AccountSwitcher: View {
    public let dotColor: Color
    public let label: String
    public let onCycle: () -> Void

    @State private var isHovered = false

    public init(dotColor: Color, label: String, onCycle: @escaping () -> Void) {
        self.dotColor = dotColor
        self.label = label
        self.onCycle = onCycle
    }

    public var body: some View {
        Button(action: onCycle) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.rbGeist(12))
                    .foregroundStyle(isHovered ? Color.rbFg1 : Color.rbFg2)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.rbFg3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovered ? Color.rbBgElev2 : Color.rbBgElev1)
            .overlay(
                Capsule()
                    .strokeBorder(Color.rbStroke1, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
