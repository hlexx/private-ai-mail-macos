import SwiftUI

/// Primary button: `rbAccent` background + `rbFgOnAccent` text.
public struct RBPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rbTextStyle(.bodySM)
            .foregroundStyle(Color.rbFgOnAccent)
            .padding(.horizontal, RBSpace.s3)
            .padding(.vertical, RBSpace.s2)
            .background(configuration.isPressed ? Color.rbAccentPress : Color.rbAccent)
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }
}

/// Secondary button: `rbBgElev2` background + `rbFg1` text.
public struct RBSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rbTextStyle(.bodySM)
            .foregroundStyle(Color.rbFg1)
            .padding(.horizontal, RBSpace.s3)
            .padding(.vertical, RBSpace.s2)
            .background(configuration.isPressed ? Color.rbBgElev3 : Color.rbBgElev2)
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }
}

/// Ghost button: transparent background with `rbFg2` text, hover shows `rbBgElev1`.
public struct RBGhostButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rbTextStyle(.bodySM)
            .foregroundStyle(Color.rbFg2)
            .padding(.horizontal, RBSpace.s3)
            .padding(.vertical, RBSpace.s2)
            .background(configuration.isPressed ? Color.rbBgElev1 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }
}

extension ButtonStyle where Self == RBPrimaryButtonStyle {
    public static var rbPrimary: RBPrimaryButtonStyle { RBPrimaryButtonStyle() }
}

extension ButtonStyle where Self == RBSecondaryButtonStyle {
    public static var rbSecondary: RBSecondaryButtonStyle { RBSecondaryButtonStyle() }
}

extension ButtonStyle where Self == RBGhostButtonStyle {
    public static var rbGhost: RBGhostButtonStyle { RBGhostButtonStyle() }
}

#if DEBUG
#Preview("Button Styles") {
    VStack(spacing: 12) {
        Button("Primary Action") {}
            .buttonStyle(.rbPrimary)
        Button("Secondary Action") {}
            .buttonStyle(.rbSecondary)
        Button("Ghost Action") {}
            .buttonStyle(.rbGhost)
    }
    .padding()
    .background(Color.rbBgCanvas)
    .preferredColorScheme(.dark)
}
#endif
