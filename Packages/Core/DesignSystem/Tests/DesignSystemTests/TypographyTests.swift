import Testing
import SwiftUI
@testable import DesignSystem

@Suite("Typography & Tokens")
struct TypographyTests {
    // MARK: - Text Styles

    @Test func allTextStylesHaveFont() {
        for style in RBTextStyle.allCases {
            // Just ensure accessing .font doesn't crash
            _ = style.font
        }
    }

    @Test func textStyleLineSpacingIsNonNegative() {
        for style in RBTextStyle.allCases {
            #expect(style.lineSpacing >= 0, "lineSpacing should be non-negative for \(style)")
        }
    }

    @Test func uppercaseStylesAreCorrect() {
        #expect(RBTextStyle.label.isUppercased == true)
        #expect(RBTextStyle.eyebrow.isUppercased == true)
        #expect(RBTextStyle.body.isUppercased == false)
        #expect(RBTextStyle.h1.isUppercased == false)
    }

    @Test func trackingValues() {
        // displayXL: -0.02 * 84 = -1.68
        #expect(abs(RBTextStyle.displayXL.tracking - (-1.68)) < 0.01)
        // h1: -0.01 * 32 = -0.32
        #expect(abs(RBTextStyle.h1.tracking - (-0.32)) < 0.01)
        // label: 0.06 * 12 = 0.72
        #expect(abs(RBTextStyle.label.tracking - 0.72) < 0.01)
        // eyebrow: 0.14 * 11 = 1.54
        #expect(abs(RBTextStyle.eyebrow.tracking - 1.54) < 0.01)
        // body: 0
        #expect(RBTextStyle.body.tracking == 0)
    }

    // MARK: - Spacing

    @Test func spacingScale() {
        #expect(RBSpace.s1 == 4)
        #expect(RBSpace.s2 == 8)
        #expect(RBSpace.s3 == 12)
        #expect(RBSpace.s4 == 16)
        #expect(RBSpace.s5 == 20)
        #expect(RBSpace.s6 == 24)
        #expect(RBSpace.s8 == 32)
        #expect(RBSpace.s10 == 40)
        #expect(RBSpace.s12 == 48)
        #expect(RBSpace.s16 == 64)
        #expect(RBSpace.s20 == 80)
    }

    // MARK: - Radii

    @Test func radiiScale() {
        #expect(RBRadius.xs == 4)
        #expect(RBRadius.sm == 6)
        #expect(RBRadius.md == 10)
        #expect(RBRadius.lg == 14)
        #expect(RBRadius.xl == 20)
        #expect(RBRadius.xl2 == 28)
        #expect(RBRadius.pill == 999)
    }

    // MARK: - Motion

    @Test func durationValues() {
        #expect(RBDuration.d1 == 0.12)
        #expect(RBDuration.d2 == 0.20)
        #expect(RBDuration.d3 == 0.32)
        #expect(RBDuration.d4 == 0.48)
    }
}
