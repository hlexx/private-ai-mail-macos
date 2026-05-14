import Foundation

/// CSS-Color-4 OKLCH → sRGB conversion.
///
/// Follows the spec path: OKLCH → OKLab → linear-sRGB → sRGB (gamma).
public enum OKLCH {
    /// Convert OKLCH (L 0…1, C ≥ 0, H in degrees) to sRGB (each 0…1, clamped).
    public static func toSRGB(l: Double, c: Double, h: Double) -> (r: Double, g: Double, b: Double) {
        let hRad = h * .pi / 180.0
        let a = c * cos(hRad)
        let b = c * sin(hRad)

        // OKLab → linear sRGB via the intermediate LMS cube-root space.
        let lms0 = l + 0.3963377774 * a + 0.2158037573 * b
        let lms1 = l - 0.1055613458 * a - 0.0638541728 * b
        let lms2 = l - 0.0894841775 * a - 1.2914855480 * b

        let lc = lms0 * lms0 * lms0
        let mc = lms1 * lms1 * lms1
        let sc = lms2 * lms2 * lms2

        let rLin =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let gLin = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let bLin = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        return (r: gammaEncode(rLin), g: gammaEncode(gLin), b: gammaEncode(bLin))
    }

    /// sRGB gamma encode (linear → display).
    private static func gammaEncode(_ v: Double) -> Double {
        let clamped = min(max(v, 0), 1)
        if clamped <= 0.0031308 {
            return clamped * 12.92
        }
        return 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
    }
}
