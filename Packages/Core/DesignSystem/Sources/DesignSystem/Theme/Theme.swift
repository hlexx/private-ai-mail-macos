import SwiftUI

/// App-wide theme preference. Persisted via `@AppStorage("rb-theme")`.
public enum RBTheme: String, CaseIterable, Sendable {
    case system
    case dark
    case light

    /// The `ColorScheme` to apply, or `nil` for system default.
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

/// A view modifier that reads the persisted theme and applies it.
public struct RBThemeModifier: ViewModifier {
    @AppStorage("rb-theme") private var themeRaw: String = RBTheme.system.rawValue

    public init() {}

    public var theme: RBTheme {
        RBTheme(rawValue: themeRaw) ?? .system
    }

    public func body(content: Content) -> some View {
        content
            .preferredColorScheme(theme.preferredColorScheme)
    }
}

extension View {
    /// Apply the user's persisted Re:Box theme preference.
    public func rbTheme() -> some View {
        modifier(RBThemeModifier())
    }
}
