import SwiftUI

#if DEBUG
/// A development-only view that renders all design tokens for visual verification.
/// Used by snapshot tests and Xcode previews to audit the design system.
public struct TokensCheatsheet: View {
    public init() {}

    private static let spacingSizes: [CGFloat] = [
        RBSpace.s1, RBSpace.s2, RBSpace.s3, RBSpace.s4, RBSpace.s5,
        RBSpace.s6, RBSpace.s8, RBSpace.s10, RBSpace.s12, RBSpace.s16, RBSpace.s20,
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RBSpace.s6) {
                textStylesSection
                spacingSection
                radiiSection
            }
            .padding(RBSpace.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.rbBgCanvas)
    }

    @ViewBuilder
    private var textStylesSection: some View {
        Text("TEXT STYLES")
            .rbTextStyle(.eyebrow)
            .foregroundStyle(Color.rbFg3)

        VStack(alignment: .leading, spacing: RBSpace.s3) {
            ForEach(RBTextStyle.allCases, id: \.self) { style in
                let label = style.isUppercased
                    ? "\(style)".uppercased()
                    : "\(style)"
                Text(label)
                    .rbTextStyle(style)
                    .foregroundStyle(Color.rbFg1)
            }
        }
    }

    @ViewBuilder
    private var spacingSection: some View {
        Text("SPACING")
            .rbTextStyle(.eyebrow)
            .foregroundStyle(Color.rbFg3)

        HStack(alignment: .bottom, spacing: RBSpace.s2) {
            ForEach(Self.spacingSizes, id: \.self) { size in
                Rectangle()
                    .fill(Color.rbAccent)
                    .frame(width: size, height: size)
            }
        }
    }

    @ViewBuilder
    private var radiiSection: some View {
        Text("RADII")
            .rbTextStyle(.eyebrow)
            .foregroundStyle(Color.rbFg3)

        HStack(spacing: RBSpace.s3) {
            radiiItem(radius: RBRadius.xs, label: "xs")
            radiiItem(radius: RBRadius.sm, label: "sm")
            radiiItem(radius: RBRadius.md, label: "md")
            radiiItem(radius: RBRadius.lg, label: "lg")
            radiiItem(radius: RBRadius.xl, label: "xl")
            radiiItem(radius: RBRadius.xl2, label: "2xl")
        }
    }

    @ViewBuilder
    private func radiiItem(radius: CGFloat, label: String) -> some View {
        VStack(spacing: RBSpace.s1) {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.rbBgElev2)
                .frame(width: 48, height: 48)
            Text(label)
                .rbTextStyle(.mono)
                .foregroundStyle(Color.rbFg3)
        }
    }
}

#Preview("Tokens Cheatsheet — Dark") {
    TokensCheatsheet()
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 800)
}

#Preview("Tokens Cheatsheet — Light") {
    TokensCheatsheet()
        .preferredColorScheme(.light)
        .frame(width: 600, height: 800)
}
#endif
