import SwiftUI

/// A toggleable filter pill used in the threadlist filter row.
/// Off state: `rbBgElev1` + `rbStroke1` border + `rbFg2` text.
/// On state: citron-tinted background + citron border + citron text.
public struct RBFilterChip: View {
    public let label: String
    public let isOn: Bool
    public let isEnabled: Bool
    public let action: () -> Void

    public init(label: String, isOn: Bool, action: @escaping () -> Void) {
        self.init(label: label, isOn: isOn, isEnabled: true, action: action)
    }

    public init(label: String, isOn: Bool, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.rbGeist(12))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minHeight: RBControlMetrics.compactHitTarget)
                .background(isOn && isEnabled ? Color.rbCitron500.opacity(0.18) : Color.rbBgElev1)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isOn && isEnabled ? Color.rbCitron500 : Color.rbStroke1, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var foregroundColor: Color {
        if !isEnabled { return .rbFg4 }
        return isOn ? .rbCitron600 : .rbFg2
    }
}

#if DEBUG
#Preview("Filter Chips") {
    HStack(spacing: 6) {
        RBFilterChip(label: "All", isOn: true) {}
        RBFilterChip(label: "Needs reply", isOn: false) {}
        RBFilterChip(label: "Has deadline", isOn: false) {}
        RBFilterChip(label: "Attachments", isOn: false) {}
        RBFilterChip(label: "AI handled", isOn: false) {}
    }
    .padding()
    .background(Color.rbBgCanvas)
    .preferredColorScheme(.dark)
}
#endif
