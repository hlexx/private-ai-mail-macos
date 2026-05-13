import SwiftUI

/// Circle avatar with optional linear-gradient background and 2-letter initials.
public struct AvatarView: View {
    public let initials: String
    public let size: CGFloat
    public let gradientColors: [Color]

    public init(name: String, size: CGFloat = 32, gradientColors: [Color]? = nil) {
        self.initials = Self.extractInitials(from: name)
        self.size = size
        self.gradientColors = gradientColors ?? Self.defaultGradient(for: name)
    }

    public init(initials: String, size: CGFloat = 32, gradientColors: [Color]) {
        self.initials = String(initials.prefix(2)).uppercased()
        self.size = size
        self.gradientColors = gradientColors
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.rbGeist(size * 0.375, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    static func extractInitials(from name: String) -> String {
        let parts = name.split(separator: " ")
        switch parts.count {
        case 0:
            return "?"
        case 1:
            return String(parts[0].prefix(2)).uppercased()
        default:
            let first = parts[0].prefix(1)
            let last = parts[parts.count - 1].prefix(1)
            return "\(first)\(last)".uppercased()
        }
    }

    static func defaultGradient(for name: String) -> [Color] {
        let hash = abs(name.utf8.reduce(0) { ($0 &* 31) &+ Int($1) })
        let palettes: [[Color]] = [
            [.rbCobalt500, .rbViolet500],
            [.rbViolet400, .rbCobalt400],
            [.rbCitron600, .rbCobalt500],
            [.rbToneJade400, .rbCobalt400],
            [.rbCobalt400, .rbCitron600],
            [.rbViolet500, .rbToneCoral400],
        ]
        return palettes[hash % palettes.count]
    }
}

#if DEBUG
#Preview("Avatars") {
    HStack(spacing: 12) {
        AvatarView(name: "John Doe", size: 32)
        AvatarView(name: "Sarah Chen", size: 32)
        AvatarView(name: "Alex", size: 28)
        AvatarView(name: "Maria Gonzalez", size: 40)
    }
    .padding()
    .background(Color.rbBgCanvas)
    .preferredColorScheme(.dark)
}
#endif
