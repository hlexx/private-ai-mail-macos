import SwiftUI

// MARK: - Raw Color Tokens
// Each value is pre-computed from the OKLCH triple in colors_and_type.css §2.
// The source OKLCH is shown in a trailing comment for traceability.

extension Color {
    // MARK: Graphite scale

    /// oklch(98% 0.005 95)
    public static let rbGraphite50 = Color(oklch: (0.98, 0.005, 95))
    /// oklch(93% 0.006 92)
    public static let rbGraphite100 = Color(oklch: (0.93, 0.006, 92))
    /// oklch(82% 0.007 90)
    public static let rbGraphite200 = Color(oklch: (0.82, 0.007, 90))
    /// oklch(68% 0.008 250)
    public static let rbGraphite300 = Color(oklch: (0.68, 0.008, 250))
    /// oklch(55% 0.010 252)
    public static let rbGraphite400 = Color(oklch: (0.55, 0.010, 252))
    /// oklch(42% 0.011 254)
    public static let rbGraphite500 = Color(oklch: (0.42, 0.011, 254))
    /// oklch(30% 0.011 256)
    public static let rbGraphite600 = Color(oklch: (0.30, 0.011, 256))
    /// oklch(22% 0.010 258)
    public static let rbGraphite700 = Color(oklch: (0.22, 0.010, 258))
    /// oklch(17% 0.009 260)
    public static let rbGraphite800 = Color(oklch: (0.17, 0.009, 260))
    /// oklch(13% 0.008 262)
    public static let rbGraphite900 = Color(oklch: (0.13, 0.008, 262))
    /// oklch(9% 0.006 264)
    public static let rbGraphite950 = Color(oklch: (0.09, 0.006, 264))

    // MARK: Citron (signature electric lime)

    /// oklch(94% 0.18 112)
    public static let rbCitron300 = Color(oklch: (0.94, 0.18, 112))
    /// oklch(90% 0.21 113)
    public static let rbCitron400 = Color(oklch: (0.90, 0.21, 113))
    /// oklch(86% 0.22 114)
    public static let rbCitron500 = Color(oklch: (0.86, 0.22, 114))
    /// oklch(74% 0.20 116)
    public static let rbCitron600 = Color(oklch: (0.74, 0.20, 116))
    /// oklch(60% 0.17 118)
    public static let rbCitron700 = Color(oklch: (0.60, 0.17, 118))

    // MARK: Cobalt

    /// oklch(78% 0.15 258)
    public static let rbCobalt300 = Color(oklch: (0.78, 0.15, 258))
    /// oklch(66% 0.20 260)
    public static let rbCobalt400 = Color(oklch: (0.66, 0.20, 260))
    /// oklch(56% 0.23 262)
    public static let rbCobalt500 = Color(oklch: (0.56, 0.23, 262))
    /// oklch(46% 0.22 264)
    public static let rbCobalt600 = Color(oklch: (0.46, 0.22, 264))

    // MARK: Violet

    /// oklch(70% 0.20 295)
    public static let rbViolet400 = Color(oklch: (0.70, 0.20, 295))
    /// oklch(60% 0.22 295)
    public static let rbViolet500 = Color(oklch: (0.60, 0.22, 295))
    /// oklch(50% 0.21 297)
    public static let rbViolet600 = Color(oklch: (0.50, 0.21, 297))

    // MARK: Chrome (soft material)

    /// oklch(86% 0.008 240)
    public static let rbChrome200 = Color(oklch: (0.86, 0.008, 240))
    /// oklch(74% 0.010 240)
    public static let rbChrome300 = Color(oklch: (0.74, 0.010, 240))
    /// oklch(60% 0.012 240)
    public static let rbChrome400 = Color(oklch: (0.60, 0.012, 240))

    // MARK: State tones

    /// oklch(82% 0.14 75) — needs reply
    public static let rbToneAmber300 = Color(oklch: (0.82, 0.14, 75))
    /// oklch(72% 0.16 70)
    public static let rbToneAmber500 = Color(oklch: (0.72, 0.16, 70))
    /// oklch(72% 0.18 28) — deadline / risk
    public static let rbToneCoral400 = Color(oklch: (0.72, 0.18, 28))
    /// oklch(54% 0.22 28)
    public static let rbToneCoral600 = Color(oklch: (0.54, 0.22, 28))
    /// oklch(74% 0.14 162) — success / logged
    public static let rbToneJade400 = Color(oklch: (0.74, 0.14, 162))
    /// oklch(58% 0.16 164)
    public static let rbToneJade600 = Color(oklch: (0.58, 0.16, 164))
    /// oklch(78% 0.07 230) — attachment / info
    public static let rbToneIce400 = Color(oklch: (0.78, 0.07, 230))
    /// oklch(60% 0.09 232)
    public static let rbToneIce600 = Color(oklch: (0.60, 0.09, 232))
}

// MARK: - OKLCH Color Initializer

extension Color {
    /// Create a Color from an OKLCH tuple (L 0…1, C, H degrees).
    init(oklch: (l: Double, c: Double, h: Double)) {
        let rgb = OKLCH.toSRGB(l: oklch.l, c: oklch.c, h: oklch.h)
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}
