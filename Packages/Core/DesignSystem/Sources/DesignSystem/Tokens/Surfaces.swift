import SwiftUI
import AppKit

// MARK: - Semantic Surface Tokens
// Resolve to different values for dark vs light, matching colors_and_type.css §3–4.

extension Color {
    // MARK: Surfaces

    public static let rbBgDeep = Color(dark: .rbGraphite950, light: .rbGraphite50)
    public static let rbBgCanvas = Color(
        dark: .rbGraphite900,
        light: Color(oklch: (0.97, 0.004, 90))
    )
    public static let rbBgElev1 = Color(
        dark: .rbGraphite800,
        light: Color(oklch: (0.95, 0.004, 90))
    )
    public static let rbBgElev2 = Color(
        dark: .rbGraphite700,
        light: Color(oklch: (0.92, 0.005, 90))
    )
    public static let rbBgElev3 = Color(
        dark: .rbGraphite600,
        light: Color(oklch: (0.88, 0.005, 90))
    )
    public static let rbBgInverse = Color(dark: .rbGraphite50, light: .rbGraphite900)

    // MARK: Foreground

    public static let rbFg1 = Color(dark: .rbGraphite50, light: .rbGraphite900)
    public static let rbFg2 = Color(dark: .rbGraphite200, light: .rbGraphite700)
    public static let rbFg3 = Color(dark: .rbGraphite300, light: .rbGraphite500)
    public static let rbFg4 = Color(dark: .rbGraphite400, light: .rbGraphite400)
    public static let rbFgInverse = Color(dark: .rbGraphite900, light: .rbGraphite50)
    public static let rbFgOnAccent = Color(dark: .rbGraphite950, light: .rbGraphite950)

    // MARK: Strokes & dividers

    /// 8% of graphite-50 (dark) / graphite-900 (light) over transparent
    public static let rbStroke1 = Color(
        dark: Color(oklch: (0.98, 0.005, 95), alpha: 0.08),
        light: Color(oklch: (0.13, 0.008, 262), alpha: 0.08)
    )
    /// 14% of graphite-50 (dark) / graphite-900 (light) over transparent
    public static let rbStroke2 = Color(
        dark: Color(oklch: (0.98, 0.005, 95), alpha: 0.14),
        light: Color(oklch: (0.13, 0.008, 262), alpha: 0.14)
    )
    public static let rbStrokeFocus: Color = .rbCitron500

    // MARK: Accents (semantic)

    public static let rbAccent: Color = .rbCitron500
    public static let rbAccentHover: Color = .rbCitron400
    public static let rbAccentPress: Color = .rbCitron600
    /// 18% citron-500
    public static let rbAccentSoft = Color(oklch: (0.86, 0.22, 114), alpha: 0.18)
    public static let rbAccentSecondary: Color = .rbCobalt500
    public static let rbAccentTertiary: Color = .rbViolet500

    // MARK: Signal pairs

    public static let rbSignalReply: Color = .rbToneAmber300
    /// 16% amber-500
    public static let rbSignalReplyBg = Color(oklch: (0.72, 0.16, 70), alpha: 0.16)
    public static let rbSignalDeadline: Color = .rbToneCoral400
    /// 22% coral-600
    public static let rbSignalDeadlineBg = Color(oklch: (0.54, 0.22, 28), alpha: 0.22)
    public static let rbSignalAttach: Color = .rbToneIce400
    /// 22% ice-600
    public static let rbSignalAttachBg = Color(oklch: (0.60, 0.09, 232), alpha: 0.22)
    public static let rbSignalSuccess: Color = .rbToneJade400
    /// 22% jade-600
    public static let rbSignalSuccessBg = Color(oklch: (0.58, 0.16, 164), alpha: 0.22)
    public static let rbSignalLocalAi: Color = .rbCitron500
    /// 14% citron-500
    public static let rbSignalLocalAiBg = Color(oklch: (0.86, 0.22, 114), alpha: 0.14)

    // MARK: Glass materials (restrained Liquid Glass)

    public static let rbGlassThin = Color(
        dark: Color(oklch: (0.17, 0.009, 260), alpha: 0.60),
        light: Color(oklch: (0.98, 0.005, 95), alpha: 0.60)
    )
    public static let rbGlassThick = Color(
        dark: Color(oklch: (0.17, 0.009, 260), alpha: 0.80),
        light: Color(oklch: (0.98, 0.005, 95), alpha: 0.80)
    )
    public static let rbGlassStroke = Color(
        dark: Color(oklch: (0.98, 0.005, 95), alpha: 0.10),
        light: Color(oklch: (0.13, 0.008, 262), alpha: 0.10)
    )
    public static let rbGlassHighlight = Color(
        dark: Color(oklch: (0.98, 0.005, 95), alpha: 0.06),
        light: Color(oklch: (0.98, 0.005, 95), alpha: 0.60)
    )
}

// MARK: - Dynamic Color Helpers

extension Color {
    /// Create a SwiftUI Color that resolves to `dark` or `light` based on the current appearance.
    init(dark: Color, light: Color) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        }))
    }

    /// Create a Color from an OKLCH tuple with an explicit alpha channel.
    init(oklch: (l: Double, c: Double, h: Double), alpha: Double) {
        let rgb = OKLCH.toSRGB(l: oklch.l, c: oklch.c, h: oklch.h)
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b, opacity: alpha)
    }
}
