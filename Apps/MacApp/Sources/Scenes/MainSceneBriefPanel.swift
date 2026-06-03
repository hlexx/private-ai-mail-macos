import BriefFeature
import DesignSystem
import SwiftUI

extension MainScene {
    var preferredBriefPlacement: BriefPanelPlacement {
        BriefPanelPlacement(rawValue: briefPlacementRaw) ?? .side
    }

    func effectiveBriefPlacement(availableWidth: CGFloat) -> BriefPanelPlacement {
        RBResponsiveLayoutPolicy.effectiveBriefPlacement(
            preferredPlacement: preferredBriefPlacement,
            availableWidth: availableWidth,
            sidebarCollapsed: sidebarCollapsed,
            briefCollapsed: briefCollapsed,
            sidebarWidth: CGFloat(sidebarWidth),
            threadListWidth: CGFloat(threadlistWidth),
            briefWidth: CGFloat(briefWidth)
        )
    }

    func effectiveBriefPanelIsBottom(availableWidth: CGFloat) -> Bool {
        effectiveBriefPlacement(availableWidth: availableWidth) == .bottom
    }

    func effectiveBriefCollapsed(briefPanelIsBottom: Bool) -> Binding<Bool> {
        Binding(
            get: { briefPanelIsBottom || briefCollapsed },
            set: { newValue in
                if !briefPanelIsBottom {
                    briefCollapsed = newValue
                }
            }
        )
    }

    @ViewBuilder
    var briefPanelContent: some View {
        if aiReady {
            BriefRail(
                store: briefStore,
                onDraftReply: { draftReply() }
            )
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            AIUnavailableRail(
                modelController: composition.aiModelController,
                openSettings: { openSettings() }
            )
        }
    }
}
