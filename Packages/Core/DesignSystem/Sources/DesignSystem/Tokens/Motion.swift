import SwiftUI

/// Duration tokens from colors_and_type.css §6.
public enum RBDuration {
    public static let d1: Double = 0.12  // hover / press
    public static let d2: Double = 0.20  // sheet, popover
    public static let d3: Double = 0.32  // brief expand, route
    public static let d4: Double = 0.48  // attachment highlights
}

/// Easing curves from colors_and_type.css §6.
public enum RBEase {
    /// cubic-bezier(.22, .61, .36, 1)
    public static let out = Animation.timingCurve(0.22, 0.61, 0.36, 1.0)

    /// cubic-bezier(.4, 0, .2, 1)
    public static let inOut = Animation.timingCurve(0.4, 0.0, 0.2, 1.0)

    /// cubic-bezier(.2, .9, .1, 1)
    public static let snap = Animation.timingCurve(0.2, 0.9, 0.1, 1.0)

    /// Convenience: ease-out with a specific duration token.
    public static func out(duration: Double) -> Animation {
        Animation.timingCurve(0.22, 0.61, 0.36, 1.0, duration: duration)
    }

    public static func inOut(duration: Double) -> Animation {
        Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: duration)
    }

    public static func snap(duration: Double) -> Animation {
        Animation.timingCurve(0.2, 0.9, 0.1, 1.0, duration: duration)
    }
}
