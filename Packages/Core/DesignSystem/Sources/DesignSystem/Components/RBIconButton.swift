import SwiftUI

/// A 28x28 square button hosting an SF Symbol with hover background.
public struct RBIconButton: View {
    private let systemName: String
    private let accessibilityLabel: String
    private let action: () -> Void

    @State private var isHovered = false

    public init(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(isHovered ? Color.rbFg1 : Color.rbFg2)
                .frame(width: 28, height: 28)
                .background(isHovered ? Color.rbBgElev1 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

#if DEBUG
#Preview("Icon Buttons") {
    HStack(spacing: 4) {
        RBIconButton(systemName: "line.3.horizontal.decrease", accessibilityLabel: "Filter") {}
        RBIconButton(systemName: "sun.max", accessibilityLabel: "Theme") {}
        RBIconButton(systemName: "gearshape", accessibilityLabel: "Settings") {}
        RBIconButton(systemName: "square.and.pencil", accessibilityLabel: "Compose") {}
    }
    .padding()
    .background(Color.rbBgCanvas)
    .preferredColorScheme(.dark)
}
#endif
