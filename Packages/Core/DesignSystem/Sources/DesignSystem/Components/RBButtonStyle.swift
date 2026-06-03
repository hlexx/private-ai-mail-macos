import SwiftUI

/// Primary button: `rbAccent` background + `rbFgOnAccent` text.
public struct RBPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        RBPrimaryButtonBody(configuration: configuration)
    }
}

private struct RBPrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RBRadius.sm)

        configuration.label
            .rbTextStyle(.bodySM)
            .foregroundStyle(isEnabled ? Color.rbFgOnAccent : Color.rbFg4)
            .padding(.horizontal, RBSpace.s3)
            .padding(.vertical, RBSpace.s2)
            .frame(minHeight: RBControlMetrics.compactHitTarget)
            .background(backgroundColor)
            .clipShape(shape)
            .contentShape(shape)
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .rbBgElev2 }
        return configuration.isPressed ? .rbAccentPress : .rbAccent
    }

}

/// Secondary button: `rbBgElev2` background + `rbFg1` text.
public struct RBSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        RBSecondaryButtonBody(configuration: configuration)
    }
}

private struct RBSecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RBRadius.sm)

        configuration.label
            .rbTextStyle(.bodySM)
            .foregroundStyle(isEnabled ? Color.rbFg1 : Color.rbFg4)
            .padding(.horizontal, RBSpace.s3)
            .padding(.vertical, RBSpace.s2)
            .frame(minHeight: RBControlMetrics.compactHitTarget)
            .background(backgroundColor)
            .clipShape(shape)
            .contentShape(shape)
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .rbBgElev1 }
        return configuration.isPressed ? .rbBgElev3 : .rbBgElev2
    }

}

/// Ghost button: transparent background with `rbFg2` text, hover shows `rbBgElev1`.
public struct RBGhostButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        RBGhostButtonBody(configuration: configuration)
    }
}

private struct RBGhostButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RBRadius.sm)

        configuration.label
            .rbTextStyle(.bodySM)
            .foregroundStyle(isEnabled ? Color.rbFg2 : Color.rbFg4)
            .padding(.horizontal, RBSpace.s3)
            .padding(.vertical, RBSpace.s2)
            .frame(minHeight: RBControlMetrics.compactHitTarget)
            .background(backgroundColor)
            .clipShape(shape)
            .contentShape(shape)
            .onHover { isHovered = isEnabled && $0 }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { isHovered = false }
            }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed { return .rbBgElev2 }
        return isHovered ? .rbBgElev1 : .clear
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
