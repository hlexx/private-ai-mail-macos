import SwiftUI

// MARK: - Font Helpers

extension Font {
    /// Geist sans-serif. Registered at app level via ATSApplicationFontsPath.
    public static func rbGeist(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold:
            name = "Geist-Bold"
        case .semibold:
            name = "Geist-SemiBold"
        case .medium:
            name = "Geist-Medium"
        default:
            name = "Geist-Regular"
        }
        return Font.custom(name, size: size, relativeTo: .body)
    }

    /// Instrument Serif italic — editorial accent.
    public static func rbSerifItalic(_ size: CGFloat) -> Font {
        Font.custom("InstrumentSerif-Italic", size: size, relativeTo: .body)
    }

    /// Instrument Serif regular.
    public static func rbSerif(_ size: CGFloat) -> Font {
        Font.custom("InstrumentSerif-Regular", size: size, relativeTo: .body)
    }

    /// JetBrains Mono — metadata, evidence, eyebrows.
    public static func rbMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold:
            name = "JetBrainsMono-SemiBold"
        case .medium:
            name = "JetBrainsMono-Medium"
        default:
            name = "JetBrainsMono-Regular"
        }
        return Font.custom(name, size: size, relativeTo: .body)
    }
}

// MARK: - Text Styles

/// Maps to the semantic typography classes in colors_and_type.css §7.
public enum RBTextStyle: CaseIterable, Sendable {
    case displayXL   // 84px, display font, weight 500, leading tight, tracking tight
    case displayLG   // 60px
    case displayMD   // 44px
    case h1          // 32px, weight 600, leading snug, tracking snug
    case h2          // 24px
    case h3          // 20px
    case h4          // 17px
    case bodyLG      // 15px, weight 400, leading normal
    case body        // 14px
    case bodySM      // 13px
    case label       // 12px, weight 600, uppercase, tracking label
    case eyebrow     // 11px, mono, weight 500, uppercase, tracking eyebrow
    case mono        // 12px, mono, weight 400, leading normal
    case editorial   // serif italic, tracking -0.005em
}

extension RBTextStyle {
    public var font: Font {
        switch self {
        case .displayXL: return .rbGeist(84, weight: .medium)
        case .displayLG: return .rbGeist(60, weight: .medium)
        case .displayMD: return .rbGeist(44, weight: .medium)
        case .h1: return .rbGeist(32, weight: .semibold)
        case .h2: return .rbGeist(24, weight: .semibold)
        case .h3: return .rbGeist(20, weight: .semibold)
        case .h4: return .rbGeist(17, weight: .semibold)
        case .bodyLG: return .rbGeist(15, weight: .regular)
        case .body: return .rbGeist(14, weight: .regular)
        case .bodySM: return .rbGeist(13, weight: .regular)
        case .label: return .rbGeist(12, weight: .semibold)
        case .eyebrow: return .rbMono(11, weight: .medium)
        case .mono: return .rbMono(12, weight: .regular)
        case .editorial: return .rbSerifItalic(14)
        }
    }

    /// Line spacing (extra leading added to the font's natural line height).
    /// Derived from the CSS leading multipliers applied to the font size.
    public var lineSpacing: CGFloat {
        switch self {
        case .displayXL, .displayLG, .displayMD:
            return 0 // leading-tight (1.1) — handled by natural font metrics
        case .h1, .h2, .h3, .h4:
            return 2 // leading-snug (1.25)
        case .bodyLG, .body, .bodySM, .mono:
            return 4 // leading-normal (1.45)
        case .label, .eyebrow:
            return 0 // line-height: 1
        case .editorial:
            return 4
        }
    }

    /// Tracking (letter spacing) in points.
    public var tracking: CGFloat {
        switch self {
        case .displayXL, .displayLG, .displayMD:
            return -0.02 * fontSize // tracking-tight
        case .h1, .h2:
            return -0.01 * fontSize // tracking-snug
        case .label:
            return 0.06 * fontSize  // tracking-label
        case .eyebrow:
            return 0.14 * fontSize  // tracking-eyebrow
        case .editorial:
            return -0.005 * fontSize
        default:
            return 0 // tracking-normal
        }
    }

    public var isUppercased: Bool {
        switch self {
        case .label, .eyebrow: return true
        default: return false
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .displayXL: return 84
        case .displayLG: return 60
        case .displayMD: return 44
        case .h1: return 32
        case .h2: return 24
        case .h3: return 20
        case .h4: return 17
        case .bodyLG: return 15
        case .body: return 14
        case .bodySM: return 13
        case .label: return 12
        case .eyebrow: return 11
        case .mono: return 12
        case .editorial: return 14
        }
    }
}

// MARK: - View Modifier

public struct RBTextStyleModifier: ViewModifier {
    let style: RBTextStyle

    public func body(content: Content) -> some View {
        content
            .font(style.font)
            .lineSpacing(style.lineSpacing)
            .tracking(style.tracking)
    }
}

extension View {
    public func rbTextStyle(_ style: RBTextStyle) -> some View {
        modifier(RBTextStyleModifier(style: style))
    }
}
