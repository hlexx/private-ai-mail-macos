import BriefFeature
import DesignSystem
import SwiftUI

extension MainScene {
    var briefPanelIsBottom: Bool {
        briefPlacementRaw == BriefPanelPlacement.bottom.rawValue
    }

    var effectiveBriefCollapsed: Binding<Bool> {
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
