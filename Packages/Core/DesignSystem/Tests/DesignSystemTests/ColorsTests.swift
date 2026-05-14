import Testing
import SwiftUI
import AppKit
@testable import DesignSystem

@Suite("OKLCH → sRGB conversion")
struct OKLCHTests {
    @Test func knownTriplets() {
        let tolerance = 1.0 / 255.0

        // Pure white: oklch(100% 0 0) → (1, 1, 1)
        let white = OKLCH.toSRGB(l: 1.0, c: 0.0, h: 0.0)
        #expect(abs(white.r - 1.0) < tolerance)
        #expect(abs(white.g - 1.0) < tolerance)
        #expect(abs(white.b - 1.0) < tolerance)

        // Pure black: oklch(0% 0 0) → (0, 0, 0)
        let black = OKLCH.toSRGB(l: 0.0, c: 0.0, h: 0.0)
        #expect(abs(black.r) < tolerance)
        #expect(abs(black.g) < tolerance)
        #expect(abs(black.b) < tolerance)

        // Citron-500: oklch(86% 0.22 114) — bright yellow-green
        let citron = OKLCH.toSRGB(l: 0.86, c: 0.22, h: 114)
        #expect(citron.r > 0.5, "Citron red channel should be medium-high")
        #expect(citron.g > 0.7, "Citron green channel should be high")
        #expect(citron.b < 0.3, "Citron blue channel should be low")
    }

    @Test func graphite900() {
        // oklch(13% 0.008 262) — very dark near-black
        let g900 = OKLCH.toSRGB(l: 0.13, c: 0.008, h: 262)
        #expect(g900.r < 0.08, "Graphite 900 should be very dark")
        #expect(g900.g < 0.08)
        #expect(g900.b < 0.10)
    }

    @Test func cobalt500() {
        // oklch(56% 0.23 262) — deep blue
        let cobalt = OKLCH.toSRGB(l: 0.56, c: 0.23, h: 262)
        #expect(cobalt.b > cobalt.r, "Cobalt should be bluer than red")
        #expect(cobalt.b > cobalt.g, "Cobalt should be bluer than green")
    }

    @Test func clampingOutOfGamut() {
        let extreme = OKLCH.toSRGB(l: 0.5, c: 0.4, h: 30)
        #expect(extreme.r >= 0.0 && extreme.r <= 1.0)
        #expect(extreme.g >= 0.0 && extreme.g <= 1.0)
        #expect(extreme.b >= 0.0 && extreme.b <= 1.0)
    }
}

@Suite("Semantic surfaces")
struct SurfaceTests {
    @Test func darkAndLightResolveDifferently() {
        let dark = NSAppearance(named: .darkAqua)!
        let light = NSAppearance(named: .aqua)!

        let nsBgCanvas = NSColor(Color.rbBgCanvas)

        var darkR: CGFloat = 0, darkG: CGFloat = 0, darkB: CGFloat = 0, darkA: CGFloat = 0
        dark.performAsCurrentDrawingAppearance {
            let resolved = nsBgCanvas.usingColorSpace(NSColorSpace.sRGB) ?? nsBgCanvas
            resolved.getRed(&darkR, green: &darkG, blue: &darkB, alpha: &darkA)
        }

        var lightR: CGFloat = 0, lightG: CGFloat = 0, lightB: CGFloat = 0, lightA: CGFloat = 0
        light.performAsCurrentDrawingAppearance {
            let resolved = nsBgCanvas.usingColorSpace(NSColorSpace.sRGB) ?? nsBgCanvas
            resolved.getRed(&lightR, green: &lightG, blue: &lightB, alpha: &lightA)
        }

        let darkLuminance = 0.2126 * darkR + 0.7152 * darkG + 0.0722 * darkB
        let lightLuminance = 0.2126 * lightR + 0.7152 * lightG + 0.0722 * lightB
        #expect(darkLuminance < 0.15, "Dark canvas should be dark (luminance: \(darkLuminance))")
        #expect(lightLuminance > 0.85, "Light canvas should be light (luminance: \(lightLuminance))")
    }

    @Test func accentColorIsConsistent() {
        let ns = NSColor(Color.rbAccent)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let resolved = ns.usingColorSpace(NSColorSpace.sRGB) ?? ns
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(g > 0.7, "Citron accent green should be high")
        #expect(b < 0.3, "Citron accent blue should be low")
    }
}
