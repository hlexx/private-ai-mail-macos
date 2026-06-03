import BriefFeature
import DesignSystem
import SwiftUI

enum BriefPanelTabRevealPolicy {
    static let draftTabRaw = "draft"
    static let briefTabRaw = "brief"

    static func shouldRevealBriefTab(
        preferredPlacement: BriefPanelPlacement,
        effectivePlacement: BriefPanelPlacement,
        sideBriefCollapsed: Bool,
        bottomPanelCollapsed: Bool,
        currentTabRaw: String
    ) -> Bool {
        preferredPlacement == .side
            && effectivePlacement == .bottom
            && !sideBriefCollapsed
            && (bottomPanelCollapsed || currentTabRaw != briefTabRaw)
    }
}

extension MainScene {
    var preferredBriefPlacement: BriefPanelPlacement {
        BriefPanelPlacement(rawValue: briefPlacementRaw) ?? .side
    }

    var briefPanelIsBottom: Bool {
        preferredBriefPlacement == .bottom
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

    func revealBriefTabIfNeeded(effectivePlacement: BriefPanelPlacement) {
        guard BriefPanelTabRevealPolicy.shouldRevealBriefTab(
            preferredPlacement: preferredBriefPlacement,
            effectivePlacement: effectivePlacement,
            sideBriefCollapsed: briefCollapsed,
            bottomPanelCollapsed: bottomPanelCollapsed,
            currentTabRaw: bottomPanelTabRaw
        ) else { return }

        bottomPanelCollapsed = false
        if bottomPanelTabRaw != BriefPanelTabRevealPolicy.briefTabRaw {
            bottomPanelTabRaw = BriefPanelTabRevealPolicy.briefTabRaw
        }
    }

    func syncBriefTabReveal<Content: View>(
        currentPlacement: BriefPanelPlacement,
        availableWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .onAppear {
                revealBriefTabIfNeeded(effectivePlacement: currentPlacement)
            }
            .onChange(of: currentPlacement) { _, newPlacement in
                revealBriefTabIfNeeded(effectivePlacement: newPlacement)
            }
            .onChange(of: briefPlacementRaw) { _, _ in
                let updatedPlacement = effectiveBriefPlacement(
                    availableWidth: availableWidth
                )
                revealBriefTabIfNeeded(effectivePlacement: updatedPlacement)
            }
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

    var sidebarFolders: [FolderItem] {
        var folders = FolderItem.defaultFolders
        let counts = inboxStore.folderCounts
        for idx in folders.indices {
            let c = counts[folders[idx].id]
            folders[idx].count = (c ?? 0) > 0 ? c : nil
        }
        return folders
    }
}
