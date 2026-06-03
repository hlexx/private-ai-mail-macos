import Testing
@testable import PrivateAIMail

@Suite("Brief panel tab reveal policy")
struct BriefPanelTabRevealPolicyTests {
    @Test func revealsBriefWhenSidePreferenceIsForcedToBottom() {
        let shouldReveal = BriefPanelTabRevealPolicy.shouldRevealBriefTab(
            preferredPlacement: .side,
            effectivePlacement: .bottom,
            sideBriefCollapsed: false,
            currentTabRaw: BriefPanelTabRevealPolicy.draftTabRaw
        )

        #expect(shouldReveal)
    }

    @Test func doesNotRevealBriefForExplicitBottomPreference() {
        let shouldReveal = BriefPanelTabRevealPolicy.shouldRevealBriefTab(
            preferredPlacement: .bottom,
            effectivePlacement: .bottom,
            sideBriefCollapsed: false,
            currentTabRaw: BriefPanelTabRevealPolicy.draftTabRaw
        )

        #expect(!shouldReveal)
    }

    @Test func doesNotRevealBriefWhenSideBriefIsCollapsed() {
        let shouldReveal = BriefPanelTabRevealPolicy.shouldRevealBriefTab(
            preferredPlacement: .side,
            effectivePlacement: .bottom,
            sideBriefCollapsed: true,
            currentTabRaw: BriefPanelTabRevealPolicy.draftTabRaw
        )

        #expect(!shouldReveal)
    }

    @Test func doesNotRewriteAnAlreadyVisibleBriefTab() {
        let shouldReveal = BriefPanelTabRevealPolicy.shouldRevealBriefTab(
            preferredPlacement: .side,
            effectivePlacement: .bottom,
            sideBriefCollapsed: false,
            currentTabRaw: BriefPanelTabRevealPolicy.briefTabRaw
        )

        #expect(!shouldReveal)
    }
}
