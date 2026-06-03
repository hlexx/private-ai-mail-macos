import Testing
import SwiftUI
import AppKit
@testable import DesignSystem

/// Compliance tests: implementation values must match the
/// **design source of truth** in `design/re-box/project/app/`.
///
/// Reference files (paths relative to repo root):
/// - `design/re-box/project/app/colors_and_type.css`  (color/type/spacing/radii/motion)
/// - `design/re-box/project/app/app.css`              (layout dimensions)
/// - `design/re-box/project/app/data.js`              (signal-chip kinds)
/// - `design/re-box/project/app/Icon.jsx`             (icon names used)
///
/// If the design moves, edit the constants in this file FIRST (so the
/// test goes red), then change the implementation, then come back here
/// and confirm parity. Do NOT skip these tests; they are the contract
/// with the Re:Box handoff.
@Suite("Design Compliance — Re:Box handoff parity")
struct DesignComplianceTests {

    // ───────────────────────────────────────────────
    // MARK: §2  Raw color tokens (OKLCH triples)
    // ───────────────────────────────────────────────

    /// Each row: `(label, oklch L, oklch C, oklch H, implementation Color)`.
    /// Triples are copied verbatim from `colors_and_type.css` §2.
    static let oklchReference: [(String, Double, Double, Double, Color)] = [
        // Graphite scale
        ("graphite-50",  0.98, 0.005,  95, .rbGraphite50),
        ("graphite-100", 0.93, 0.006,  92, .rbGraphite100),
        ("graphite-200", 0.82, 0.007,  90, .rbGraphite200),
        ("graphite-300", 0.68, 0.008, 250, .rbGraphite300),
        ("graphite-400", 0.55, 0.010, 252, .rbGraphite400),
        ("graphite-500", 0.42, 0.011, 254, .rbGraphite500),
        ("graphite-600", 0.30, 0.011, 256, .rbGraphite600),
        ("graphite-700", 0.22, 0.010, 258, .rbGraphite700),
        ("graphite-800", 0.17, 0.009, 260, .rbGraphite800),
        ("graphite-900", 0.13, 0.008, 262, .rbGraphite900),
        ("graphite-950", 0.09, 0.006, 264, .rbGraphite950),

        // Citron — signature electric lime
        ("citron-300", 0.94, 0.18, 112, .rbCitron300),
        ("citron-400", 0.90, 0.21, 113, .rbCitron400),
        ("citron-500", 0.86, 0.22, 114, .rbCitron500),
        ("citron-600", 0.74, 0.20, 116, .rbCitron600),
        ("citron-700", 0.60, 0.17, 118, .rbCitron700),

        // Cobalt
        ("cobalt-300", 0.78, 0.15, 258, .rbCobalt300),
        ("cobalt-400", 0.66, 0.20, 260, .rbCobalt400),
        ("cobalt-500", 0.56, 0.23, 262, .rbCobalt500),
        ("cobalt-600", 0.46, 0.22, 264, .rbCobalt600),

        // Violet
        ("violet-400", 0.70, 0.20, 295, .rbViolet400),
        ("violet-500", 0.60, 0.22, 295, .rbViolet500),
        ("violet-600", 0.50, 0.21, 297, .rbViolet600),

        // Soft Chrome material
        ("chrome-200", 0.86, 0.008, 240, .rbChrome200),
        ("chrome-300", 0.74, 0.010, 240, .rbChrome300),
        ("chrome-400", 0.60, 0.012, 240, .rbChrome400),

        // State tones
        ("tone-amber-300", 0.82, 0.14,  75, .rbToneAmber300),
        ("tone-amber-500", 0.72, 0.16,  70, .rbToneAmber500),
        ("tone-coral-400", 0.72, 0.18,  28, .rbToneCoral400),
        ("tone-coral-600", 0.54, 0.22,  28, .rbToneCoral600),
        ("tone-jade-400",  0.74, 0.14, 162, .rbToneJade400),
        ("tone-jade-600",  0.58, 0.16, 164, .rbToneJade600),
        ("tone-ice-400",   0.78, 0.07, 230, .rbToneIce400),
        ("tone-ice-600",   0.60, 0.09, 232, .rbToneIce600),
    ]

    @Test("Every raw color token resolves to the OKLCH-derived sRGB in CSS §2")
    func colorTokensMatchOKLCH() throws {
        for (label, l, c, h, color) in Self.oklchReference {
            let expected = OKLCH.toSRGB(l: l, c: c, h: h)
            let actual = try Self.sRGBComponents(of: color)

            let dr = abs(actual.r - expected.r)
            let dg = abs(actual.g - expected.g)
            let db = abs(actual.b - expected.b)

            #expect(dr <= 0.005,
                "[\(label)] R drift \(dr) — actual \(actual.r), expected \(expected.r)")
            #expect(dg <= 0.005,
                "[\(label)] G drift \(dg) — actual \(actual.g), expected \(expected.g)")
            #expect(db <= 0.005,
                "[\(label)] B drift \(db) — actual \(actual.b), expected \(expected.b)")
        }
    }

    // ───────────────────────────────────────────────
    // MARK: §6  Spacing scale
    // ───────────────────────────────────────────────

    @Test("RBSpace tokens equal CSS §6 --space-* literals")
    func spacingTokensMatchCSS() {
        #expect(RBSpace.s1  == 4)
        #expect(RBSpace.s2  == 8)
        #expect(RBSpace.s3  == 12)
        #expect(RBSpace.s4  == 16)
        #expect(RBSpace.s5  == 20)
        #expect(RBSpace.s6  == 24)
        #expect(RBSpace.s8  == 32)
        #expect(RBSpace.s10 == 40)
        #expect(RBSpace.s12 == 48)
        #expect(RBSpace.s16 == 64)
        #expect(RBSpace.s20 == 80)
    }

    // ───────────────────────────────────────────────
    // MARK: §6  Corner radii
    // ───────────────────────────────────────────────

    @Test("RBRadius tokens equal CSS §6 --radius-* literals")
    func radiiTokensMatchCSS() {
        #expect(RBRadius.xs   == 4)
        #expect(RBRadius.sm   == 6)
        #expect(RBRadius.md   == 10)
        #expect(RBRadius.lg   == 14)
        #expect(RBRadius.xl   == 20)
        #expect(RBRadius.xl2  == 28)
        #expect(RBRadius.pill == 999)
    }

    // ───────────────────────────────────────────────
    // MARK: §6  Motion durations
    // ───────────────────────────────────────────────

    @Test("RBDuration tokens equal CSS §6 --dur-* literals (ms → seconds)")
    func motionDurationsMatchCSS() {
        #expect(RBDuration.d1 == 0.120)
        #expect(RBDuration.d2 == 0.200)
        #expect(RBDuration.d3 == 0.320)
        #expect(RBDuration.d4 == 0.480)
    }

    // ───────────────────────────────────────────────
    // MARK: §5  Typography sizes
    // ───────────────────────────────────────────────

    @Test("RBTextStyle.fontSize matches CSS §5 --type-* and §7 class sizes")
    func typographyFontSizesMatchCSS() {
        #expect(RBTextStyle.displayXL.fontSize == 84) // --type-6xl
        #expect(RBTextStyle.displayLG.fontSize == 60) // --type-5xl
        #expect(RBTextStyle.displayMD.fontSize == 44) // --type-4xl
        #expect(RBTextStyle.h1.fontSize        == 32) // --type-3xl
        #expect(RBTextStyle.h2.fontSize        == 24) // --type-2xl
        #expect(RBTextStyle.h3.fontSize        == 20) // --type-xl
        #expect(RBTextStyle.h4.fontSize        == 17) // --type-lg
        #expect(RBTextStyle.bodyLG.fontSize    == 15) // --type-md
        #expect(RBTextStyle.body.fontSize      == 14) // --type-base
        #expect(RBTextStyle.bodySM.fontSize    == 13) // --type-sm
        #expect(RBTextStyle.label.fontSize     == 12) // --type-xs
        #expect(RBTextStyle.eyebrow.fontSize   == 11) // --type-2xs
        #expect(RBTextStyle.mono.fontSize      == 12) // --type-xs
    }

    @Test("Tracking ratios match CSS §5 --tracking-* (× fontSize)")
    func typographyTrackingMatchesCSS() {
        // --tracking-tight: -0.02em
        #expect(RBTextStyle.displayXL.tracking == -0.02 * 84)
        // --tracking-snug: -0.01em
        #expect(RBTextStyle.h1.tracking        == -0.01 * 32)
        // --tracking-label: 0.06em
        #expect(RBTextStyle.label.tracking     ==  0.06 * 12)
        // --tracking-eyebrow: 0.14em
        #expect(RBTextStyle.eyebrow.tracking   ==  0.14 * 11)
        // --editorial: -0.005em
        #expect(RBTextStyle.editorial.tracking == -0.005 * 14)
    }

    @Test("Uppercased styles match CSS §7 (`text-transform: uppercase`)")
    func typographyUppercasedMatchesCSS() {
        #expect(RBTextStyle.label.isUppercased   == true)
        #expect(RBTextStyle.eyebrow.isUppercased == true)
        #expect(RBTextStyle.body.isUppercased    == false)
        #expect(RBTextStyle.h1.isUppercased      == false)
    }

    // ───────────────────────────────────────────────
    // MARK: app.css  Layout dimensions
    // ───────────────────────────────────────────────

    @Test("RBLayout matches app.css window + panes + read-body grids")
    func layoutDimensionsMatchAppCSS() {
        // .rb-window { grid-template-rows: 56px 1fr }
        #expect(RBLayout.toolbarHeight  == 56)

        // .rb-panes { grid-template-columns: 240px 360px 1fr }
        #expect(RBLayout.sidebarWidth    == 240)
        #expect(RBLayout.threadListWidth == 360)

        // .rb-read-body { grid-template-columns: minmax(0, 1fr) 340px }
        #expect(RBLayout.briefRailWidth  == 340)

        // .rb-row .av { width: 32px }
        #expect(RBLayout.threadListAvatarSize == 32)

        // .rb-msg-av { width: 28px }
        #expect(RBLayout.messageAvatarSize == 28)

        // .rb-row.active::before { width: 3px }
        #expect(RBLayout.activeRowIndicatorWidth == 3)

    }

    // ───────────────────────────────────────────────
    // MARK: Signal chip coverage
    // ───────────────────────────────────────────────

    /// `design/re-box/project/app/ThreadList.jsx` switches on these `kind`
    /// values. Every one must have a corresponding `SignalChip.Kind` case so
    /// real thread data can be rendered without falling through.
    @Test("Every signal-chip kind from data.js maps to a SignalChip.Kind case")
    func signalChipKindsCoverDesign() {
        let designKinds = [
            ("due",    SignalChip.Kind.due(label: "Fri", urgent: false)),
            ("reply",  SignalChip.Kind.reply(label: "Wed")),
            ("att",    SignalChip.Kind.att(pages: 3)),
            ("ai",     SignalChip.Kind.ai(label: "AI")),
            ("logged", SignalChip.Kind.logged(target: "HubSpot")),
            ("cc",     SignalChip.Kind.cc(label: "+ legal")),
            ("cal",    SignalChip.Kind.cal(label: "Tue 4pm")),
            ("paid",   SignalChip.Kind.paid(label: "€1,840")),
        ]
        for (label, kind) in designKinds {
            // Just constructing each variant is the assertion: a compile error
            // means a case from data.js is missing from the implementation.
            #expect(String(describing: kind).isEmpty == false, "[\(label)] no representation")
        }
    }

    // ───────────────────────────────────────────────
    // MARK: Helpers
    // ───────────────────────────────────────────────

    private static func sRGBComponents(of color: Color) throws -> (r: Double, g: Double, b: Double) {
        let ns = NSColor(color)
        guard let conv = ns.usingColorSpace(.sRGB) else {
            throw ComplianceError.colorConversionFailed
        }
        return (r: Double(conv.redComponent),
                g: Double(conv.greenComponent),
                b: Double(conv.blueComponent))
    }

    enum ComplianceError: Error {
        case colorConversionFailed
    }
}
