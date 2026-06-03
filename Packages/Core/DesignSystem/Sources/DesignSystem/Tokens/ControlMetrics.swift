import Foundation

/// Shared sizing contracts for dense interactive controls.
public enum RBControlMetrics {
    /// Stable compact desktop target for frequently repeated controls.
    public static let compactHitTarget: CGFloat = 32

    public static let iconButtonTargetSize: CGFloat = compactHitTarget
    public static let filterChipMinHeight: CGFloat = compactHitTarget
    public static let buttonMinHeight: CGFloat = compactHitTarget
    public static let toneSegmentMinHeight: CGFloat = compactHitTarget
}
