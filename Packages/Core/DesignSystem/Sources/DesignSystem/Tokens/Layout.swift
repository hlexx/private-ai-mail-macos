import Foundation

/// Layout dimensions for the macOS window chrome and primary panes.
///
/// Values are pulled verbatim from `design/re-box/project/app/app.css`
/// (see Re:Box handoff). Treat these as the source of truth; any view
/// that hard-codes a competing literal is a bug.
public enum RBLayout {
    // MARK: Window chrome

    /// `.rb-window { grid-template-rows: 56px 1fr }`
    public static let toolbarHeight: CGFloat = 56

    /// `.rb-window` min content width target (supports 4-pane layout: 180+280+480+0).
    public static let windowMinWidth: CGFloat = 980

    /// `.rb-window` min content height target.
    public static let windowMinHeight: CGFloat = 720

    // MARK: Three-pane layout

    /// `.rb-panes { grid-template-columns: 240px ... }`
    public static let sidebarWidth: CGFloat = 240
    public static let sidebarMinWidth: CGFloat = 180
    public static let sidebarMaxWidth: CGFloat = 320

    /// `.rb-panes { grid-template-columns: ... 360px ... }`
    public static let threadListWidth: CGFloat = 360
    public static let threadListMinWidth: CGFloat = 280
    public static let threadListMaxWidth: CGFloat = 480

    // MARK: Reading-pane inner split

    /// `.rb-read-body { grid-template-columns: minmax(0, 1fr) 340px }`
    public static let briefRailWidth: CGFloat = 340
    public static let briefRailMinWidth: CGFloat = 280
    public static let briefRailMaxWidth: CGFloat = 420

    /// Minimum reading width before the brief should move out of the side rail.
    public static let readingMinWidth: CGFloat = 480

    // MARK: Bottom work panel

    public static let bottomPanelCollapsedHeight: CGFloat = 42
    public static let bottomPanelExpandedHeight: CGFloat = 318
    public static let bottomPanelMinExpandedHeight: CGFloat = 220
    public static let bottomPanelMinReadingHeight: CGFloat = 320

    // MARK: Avatar / signal sizes

    /// `.rb-row .av { width: 32px; height: 32px }`
    public static let threadListAvatarSize: CGFloat = 32

    /// `.rb-msg-av { width: 28px; height: 28px }`
    public static let messageAvatarSize: CGFloat = 28

    /// `.rb-row.active::before { width: 3px }` — citron active-row indicator.
    public static let activeRowIndicatorWidth: CGFloat = 3

    // MARK: Settings window

    /// `SettingsScene` TabView. Matches the design system's intended dialog scale.
    public static let settingsWidth: CGFloat = 520
    public static let settingsHeight: CGFloat = 360
}

public enum RBBriefPanelPlacement: String, Equatable {
    case side
    case bottom
}

public enum RBResponsiveLayoutPolicy {
    public static func minimumWidthForSideBrief(
        sidebarCollapsed: Bool,
        sidebarWidth: CGFloat = RBLayout.sidebarWidth,
        threadListWidth: CGFloat = RBLayout.threadListWidth,
        briefWidth: CGFloat = RBLayout.briefRailWidth
    ) -> CGFloat {
        let effectiveSidebarWidth = sidebarCollapsed
            ? 0
            : sidebarWidth.clamped(to: RBLayout.sidebarMinWidth...RBLayout.sidebarMaxWidth)
        let effectiveThreadListWidth = threadListWidth.clamped(
            to: RBLayout.threadListMinWidth...RBLayout.threadListMaxWidth
        )
        let effectiveBriefWidth = briefWidth.clamped(
            to: RBLayout.briefRailMinWidth...RBLayout.briefRailMaxWidth
        )

        return effectiveSidebarWidth
            + effectiveThreadListWidth
            + RBLayout.readingMinWidth
            + effectiveBriefWidth
    }

    public static func effectiveBriefPlacement(
        preferredPlacement: RBBriefPanelPlacement,
        availableWidth: CGFloat,
        sidebarCollapsed: Bool,
        briefCollapsed: Bool,
        sidebarWidth: CGFloat = RBLayout.sidebarWidth,
        threadListWidth: CGFloat = RBLayout.threadListWidth,
        briefWidth: CGFloat = RBLayout.briefRailWidth
    ) -> RBBriefPanelPlacement {
        guard preferredPlacement == .side, !briefCollapsed else {
            return preferredPlacement
        }

        let requiredWidth = minimumWidthForSideBrief(
            sidebarCollapsed: sidebarCollapsed,
            sidebarWidth: sidebarWidth,
            threadListWidth: threadListWidth,
            briefWidth: briefWidth
        )
        return availableWidth >= requiredWidth ? .side : .bottom
    }

    public static func expandedBottomPanelHeight(
        availableHeight: CGFloat,
        preferredHeight: CGFloat = RBLayout.bottomPanelExpandedHeight
    ) -> CGFloat {
        let maximumHeight = availableHeight - RBLayout.bottomPanelMinReadingHeight
        guard maximumHeight >= RBLayout.bottomPanelMinExpandedHeight else {
            return max(RBLayout.bottomPanelCollapsedHeight, maximumHeight)
        }
        return min(preferredHeight, maximumHeight)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
