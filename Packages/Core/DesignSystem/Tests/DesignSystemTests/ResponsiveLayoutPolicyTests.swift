import Testing
@testable import DesignSystem

@Suite("Responsive layout policy")
struct ResponsiveLayoutPolicyTests {
    @Test("Side brief minimum width uses current pane widths")
    func sideBriefMinimumWidthUsesCurrentPaneWidths() {
        let requiredWidth = RBResponsiveLayoutPolicy.minimumWidthForSideBrief(
            sidebarCollapsed: false,
            sidebarWidth: RBLayout.sidebarWidth,
            threadListWidth: RBLayout.threadListWidth,
            briefWidth: RBLayout.briefRailWidth
        )

        #expect(requiredWidth == 1_420)
    }

    @Test("Side brief minimum width excludes collapsed sidebar")
    func sideBriefMinimumWidthExcludesCollapsedSidebar() {
        let requiredWidth = RBResponsiveLayoutPolicy.minimumWidthForSideBrief(
            sidebarCollapsed: true,
            sidebarWidth: RBLayout.sidebarWidth,
            threadListWidth: RBLayout.threadListWidth,
            briefWidth: RBLayout.briefRailWidth
        )

        #expect(requiredWidth == 1_180)
    }

    @Test("Side brief minimum width clamps stored pane widths")
    func sideBriefMinimumWidthClampsStoredPaneWidths() {
        let requiredWidth = RBResponsiveLayoutPolicy.minimumWidthForSideBrief(
            sidebarCollapsed: false,
            sidebarWidth: 10_000,
            threadListWidth: 1,
            briefWidth: 10_000
        )

        #expect(requiredWidth == 1_500)
    }

    @Test("Effective placement preserves side preference when width is sufficient")
    func effectivePlacementPreservesSideWhenWidthIsSufficient() {
        let placement = RBResponsiveLayoutPolicy.effectiveBriefPlacement(
            preferredPlacement: .side,
            availableWidth: 1_420,
            sidebarCollapsed: false,
            briefCollapsed: false
        )

        #expect(placement == .side)
    }

    @Test("Effective placement moves side preference to bottom when width is constrained")
    func effectivePlacementMovesSideToBottomWhenWidthIsConstrained() {
        let placement = RBResponsiveLayoutPolicy.effectiveBriefPlacement(
            preferredPlacement: .side,
            availableWidth: 1_419,
            sidebarCollapsed: false,
            briefCollapsed: false
        )

        #expect(placement == .bottom)
    }

    @Test("Effective placement does not rewrite explicit bottom or collapsed side states")
    func effectivePlacementPreservesExplicitStates() {
        let explicitBottom = RBResponsiveLayoutPolicy.effectiveBriefPlacement(
            preferredPlacement: .bottom,
            availableWidth: 2_000,
            sidebarCollapsed: false,
            briefCollapsed: false
        )
        let collapsedSide = RBResponsiveLayoutPolicy.effectiveBriefPlacement(
            preferredPlacement: .side,
            availableWidth: 900,
            sidebarCollapsed: false,
            briefCollapsed: true
        )

        #expect(explicitBottom == .bottom)
        #expect(collapsedSide == .side)
    }

    @Test("Expanded bottom panel height keeps reading area available")
    func expandedBottomPanelHeightKeepsReadingAreaAvailable() {
        #expect(RBResponsiveLayoutPolicy.expandedBottomPanelHeight(availableHeight: 900) == 318)
        #expect(RBResponsiveLayoutPolicy.expandedBottomPanelHeight(availableHeight: 560) == 240)
        #expect(RBResponsiveLayoutPolicy.expandedBottomPanelHeight(availableHeight: 500) == 180)
    }
}
