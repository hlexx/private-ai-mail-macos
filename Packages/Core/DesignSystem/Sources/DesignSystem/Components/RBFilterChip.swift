import SwiftUI

/// A toggleable filter pill used in the threadlist filter row.
/// Off state: `rbBgElev1` + `rbStroke1` border + `rbFg2` text.
/// On state: citron-tinted background + citron border + citron text.
public struct RBFilterChip: View {
    public let label: String
    public let isOn: Bool
    public let action: () -> Void

    public init(label: String, isOn: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.rbGeist(12))
                .foregroundStyle(isOn ? Color.rbCitron600 : Color.rbFg2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isOn ? Color.rbCitron500.opacity(0.18) : Color.rbBgElev1)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isOn ? Color.rbCitron500 : Color.rbStroke1, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
