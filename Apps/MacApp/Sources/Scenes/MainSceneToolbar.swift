import DesignSystem
import SwiftUI

extension MainScene {
    private var toolbarSearchText: Binding<String> {
        Binding(
            get: { inboxStore.searchText },
            set: { inboxStore.searchText = $0 }
        )
    }

    func toolbar(briefPanelIsBottom: Bool) -> some View {
        let preferredBriefPanelIsBottom = preferredBriefPlacement == .bottom

        return RBToolbar(
            accounts: accounts,
            activeAccountID: composition.activeAccountID,
            onCycleAccount: { composition.cycleActiveAccount(accounts: accounts) },
            onToggleTheme: { toggleTheme() },
            onOpenSettings: { openSettings() },
            onCompose: {
                prepareNewCompose()
                composition.showCompose = true
            },
            onToggleSidebar: { withAnimation { sidebarCollapsed.toggle() } },
            onToggleBrief: briefPanelIsBottom ? nil : { withAnimation { briefCollapsed.toggle() } },
            briefPlacementIsBottom: preferredBriefPanelIsBottom,
            onToggleBriefPlacement: {
                withAnimation {
                    if preferredBriefPanelIsBottom {
                        moveBriefToSide()
                    } else {
                        moveBriefToBottom()
                    }
                }
            },
            sidebarWidth: CGFloat(sidebarWidth),
            sidebarCollapsed: sidebarCollapsed,
            filterMenu: RBToolbarFilterMenu(
                selectedFilter: inboxStore.filter,
                onSelect: { inboxStore.filter = $0 }
            ),
            searchFocused: $searchFocused,
            searchText: toolbarSearchText,
            onSubmitSearch: { inboxStore.submitSearch() }
        )
    }
}
