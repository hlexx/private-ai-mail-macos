import DesignSystem
import Testing
@testable import PrivateAIMail

@Suite("MainScene layout policy")
struct MainSceneLayoutPolicyTests {
    @Test func storageKeysPreserveExistingLayoutDefaults() {
        #expect(MainSceneLayoutStorageKey.sidebarWidth == "pam.layout.sidebar")
        #expect(MainSceneLayoutStorageKey.threadListWidth == "pam.layout.threadlist")
        #expect(MainSceneLayoutStorageKey.briefWidth == "pam.layout.brief")
        #expect(MainSceneLayoutStorageKey.sidebarCollapsed == "pam.layout.sidebarCollapsed")
        #expect(MainSceneLayoutStorageKey.briefCollapsed == "pam.layout.briefCollapsed")
        #expect(MainSceneLayoutStorageKey.briefPlacement == "pam.layout.briefPlacement")
        #expect(MainSceneLayoutStorageKey.bottomPanelCollapsed == "pam.layout.threadBottomPanelCollapsed")
        #expect(MainSceneLayoutStorageKey.bottomPanelTab == "pam.layout.threadBottomPanelTab")
    }

    @Test func invalidStoredPlacementFallsBackToSide() {
        let state = makeState(preferredBriefPlacementRaw: "unknown")

        #expect(state.preferredBriefPlacement == .side)
    }

    @Test func narrowWindowMovesSideBriefToBottomSplitConfiguration() {
        let state = makeState(preferredBriefPlacementRaw: BriefPanelPlacement.side.rawValue)
        let configuration = state.splitConfiguration(availableWidth: RBLayout.windowMinWidth)

        #expect(configuration.effectiveBriefPlacement == .bottom)
        #expect(configuration.showsBottomBrief)
        #expect(configuration.forceSideBriefCollapsed)
    }

    @Test func collapsedSideBriefDoesNotForceBottomConfiguration() {
        let state = makeState(
            preferredBriefPlacementRaw: BriefPanelPlacement.side.rawValue,
            briefCollapsed: true
        )
        let configuration = state.splitConfiguration(availableWidth: RBLayout.windowMinWidth)

        #expect(configuration.effectiveBriefPlacement == .side)
        #expect(!configuration.showsBottomBrief)
        #expect(!configuration.forceSideBriefCollapsed)
    }

    @Test func explicitBottomPreferenceForcesSideBriefCollapsed() {
        let state = makeState(preferredBriefPlacementRaw: BriefPanelPlacement.bottom.rawValue)
        let configuration = state.splitConfiguration(availableWidth: 2_000)

        #expect(configuration.effectiveBriefPlacement == .bottom)
        #expect(configuration.showsBottomBrief)
        #expect(configuration.forceSideBriefCollapsed)
    }

    private func makeState(
        preferredBriefPlacementRaw: String = BriefPanelPlacement.side.rawValue,
        sidebarCollapsed: Bool = false,
        briefCollapsed: Bool = false,
        sidebarWidth: Double = Double(RBLayout.sidebarWidth),
        threadListWidth: Double = Double(RBLayout.threadListWidth),
        briefWidth: Double = Double(RBLayout.briefRailWidth)
    ) -> MainSceneLayoutState {
        MainSceneLayoutState(
            preferredBriefPlacementRaw: preferredBriefPlacementRaw,
            sidebarCollapsed: sidebarCollapsed,
            briefCollapsed: briefCollapsed,
            sidebarWidth: sidebarWidth,
            threadListWidth: threadListWidth,
            briefWidth: briefWidth
        )
    }
}
