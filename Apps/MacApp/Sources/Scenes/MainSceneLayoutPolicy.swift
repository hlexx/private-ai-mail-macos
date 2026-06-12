import CoreGraphics
import DesignSystem

enum MainSceneLayoutStorageKey {
    static let sidebarWidth = "pam.layout.sidebar"
    static let threadListWidth = "pam.layout.threadlist"
    static let briefWidth = "pam.layout.brief"
    static let sidebarCollapsed = "pam.layout.sidebarCollapsed"
    static let briefCollapsed = "pam.layout.briefCollapsed"
    static let briefPlacement = "pam.layout.briefPlacement"
    static let bottomPanelCollapsed = "pam.layout.threadBottomPanelCollapsed"
    static let bottomPanelTab = "pam.layout.threadBottomPanelTab"
}

struct MainSceneLayoutState: Equatable {
    var preferredBriefPlacement: BriefPanelPlacement
    var sidebarCollapsed: Bool
    var briefCollapsed: Bool
    var sidebarWidth: CGFloat
    var threadListWidth: CGFloat
    var briefWidth: CGFloat

    init(
        preferredBriefPlacementRaw: String,
        sidebarCollapsed: Bool,
        briefCollapsed: Bool,
        sidebarWidth: Double,
        threadListWidth: Double,
        briefWidth: Double
    ) {
        self.preferredBriefPlacement = BriefPanelPlacement(rawValue: preferredBriefPlacementRaw) ?? .side
        self.sidebarCollapsed = sidebarCollapsed
        self.briefCollapsed = briefCollapsed
        self.sidebarWidth = CGFloat(sidebarWidth)
        self.threadListWidth = CGFloat(threadListWidth)
        self.briefWidth = CGFloat(briefWidth)
    }

    func effectiveBriefPlacement(availableWidth: CGFloat) -> BriefPanelPlacement {
        RBResponsiveLayoutPolicy.effectiveBriefPlacement(
            preferredPlacement: preferredBriefPlacement,
            availableWidth: availableWidth,
            sidebarCollapsed: sidebarCollapsed,
            briefCollapsed: briefCollapsed,
            sidebarWidth: sidebarWidth,
            threadListWidth: threadListWidth,
            briefWidth: briefWidth
        )
    }

    func splitConfiguration(availableWidth: CGFloat) -> MainSceneSplitConfiguration {
        MainSceneSplitConfiguration(
            effectiveBriefPlacement: effectiveBriefPlacement(availableWidth: availableWidth)
        )
    }
}

struct MainSceneSplitConfiguration: Equatable {
    var effectiveBriefPlacement: BriefPanelPlacement

    var showsBottomBrief: Bool {
        effectiveBriefPlacement == .bottom
    }

    var forceSideBriefCollapsed: Bool {
        showsBottomBrief
    }
}
