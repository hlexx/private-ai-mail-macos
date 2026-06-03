import DesignSystem
import InboxFeature
import Persistence
import SwiftUI

struct RBToolbarFilterMenu {
    let selectedFilter: ThreadFilter
    let onSelect: (ThreadFilter) -> Void

    func select(_ filter: ThreadFilter) {
        onSelect(filter)
    }
}

struct RBToolbar: View {

    let accounts: [AccountRecord]
    let activeAccountID: String?
    let onCycleAccount: () -> Void
    let onToggleTheme: () -> Void
    let onOpenSettings: () -> Void
    let onCompose: () -> Void
    var onToggleSidebar: (() -> Void)?
    var onToggleBrief: (() -> Void)?
    var briefPlacementIsBottom: Bool = false
    var onToggleBriefPlacement: (() -> Void)?
    var sidebarWidth: CGFloat = RBLayout.sidebarWidth
    var sidebarCollapsed: Bool = false
    let filterMenu: RBToolbarFilterMenu
    var searchFocused: FocusState<Bool>.Binding
    @Binding var searchText: String
    let onSubmitSearch: () -> Void

    @State private var filterPopoverPresented = false
    @AppStorage("rb-theme") private var themeRaw: String = RBTheme.system.rawValue
    private var theme: RBTheme {
        RBTheme(rawValue: themeRaw) ?? .system
    }

    private var activeAccount: AccountRecord? {
        if let id = activeAccountID {
            return accounts.first(where: { $0.id == id })
        }
        return accounts.first
    }

    var body: some View {
        HStack(spacing: 0) {
            leadingSection
                .frame(width: sidebarCollapsed ? 68 : sidebarWidth, alignment: .leading)

            trailingSection
        }
        .frame(height: RBLayout.toolbarHeight)
        .padding(.leading, RBSpace.s3)
        .padding(.trailing, RBSpace.s4)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }

    private var leadingSection: some View {
        HStack(spacing: 14) {
            if !sidebarCollapsed {
                Spacer()
                    .frame(width: 68)
            }

            if let toggle = onToggleSidebar {
                RBIconButton(
                    systemName: "sidebar.leading",
                    accessibilityLabel: String(localized: "toolbar.toggleSidebar", defaultValue: "Toggle Sidebar"),
                    action: toggle
                )
            }

            if let account = activeAccount {
                AccountSwitcher(
                    dotColor: dotColor(for: account),
                    label: account.email,
                    onCycle: onCycleAccount
                )
            }
        }
    }

    private var trailingSection: some View {
        HStack(spacing: RBSpace.s2) {
            SearchField(text: $searchText, isFocused: searchFocused, onCommit: onSubmitSearch)
                .frame(maxWidth: 480)

            Spacer(minLength: RBSpace.s2)

            HStack(spacing: 4) {
                filterButton

                RBIconButton(
                    systemName: themeIconName,
                    accessibilityLabel: themeAccessibilityLabel,
                    action: onToggleTheme
                )

                if let toggle = onToggleBrief {
                    RBIconButton(
                        systemName: "sidebar.trailing",
                        accessibilityLabel: String(localized: "toolbar.toggleBrief", defaultValue: "Toggle Brief"),
                        action: toggle
                    )
                }

                if let togglePlacement = onToggleBriefPlacement {
                    RBIconButton(
                        systemName: briefPlacementIcon,
                        accessibilityLabel: briefPlacementAccessibilityLabel,
                        action: togglePlacement
                    )
                    .help(briefPlacementAccessibilityLabel)
                }

                RBIconButton(
                    systemName: "gearshape",
                    accessibilityLabel: String(localized: "toolbar.settings", defaultValue: "Settings")
                ) {
                    onOpenSettings()
                }

                RBIconButton(
                    systemName: "square.and.pencil",
                    accessibilityLabel: String(localized: "toolbar.compose", defaultValue: "Compose"),
                    action: onCompose
                )
            }
        }
    }

    private var filterButton: some View {
        RBIconButton(
            systemName: "line.3.horizontal.decrease",
            accessibilityLabel: filterAccessibilityLabel,
            action: { filterPopoverPresented.toggle() }
        )
        .help(filterHelpText)
        .popover(isPresented: $filterPopoverPresented, arrowEdge: .top) {
            RBToolbarFilterPopover(
                menu: filterMenu,
                onSelect: { filter in
                    filterMenu.select(filter)
                    filterPopoverPresented = false
                }
            )
        }
    }

    private var filterAccessibilityLabel: String {
        "\(localizedFilterCurrentPrefix)\(filterMenu.selectedFilter.label)"
    }

    private var filterHelpText: String {
        "\(localizedFilterHelpPrefix)\(filterMenu.selectedFilter.label)"
    }

    private var localizedFilterCurrentPrefix: String {
        String(localized: "toolbar.filter.currentPrefix", defaultValue: "Filter: ")
    }

    private var localizedFilterHelpPrefix: String {
        String(
            localized: "toolbar.filter.helpPrefix",
            defaultValue: "Filter inbox threads. Current filter: "
        )
    }

    private var themeIconName: String {
        switch theme {
        case .light: return "moon"
        case .dark: return "sun.max"
        case .system: return "circle.lefthalf.filled"
        }
    }

    private var themeAccessibilityLabel: String {
        switch theme {
        case .light: return "Switch to dark"
        case .dark: return "Switch to light"
        case .system: return "Switch to dark"
        }
    }

    private var briefPlacementIcon: String {
        briefPlacementIsBottom ? "sidebar.right" : "rectangle.bottomthird.inset.filled"
    }

    private var briefPlacementAccessibilityLabel: String {
        briefPlacementIsBottom
            ? String(localized: "toolbar.moveBriefToSide", defaultValue: "Move Brief to side panel")
            : String(localized: "toolbar.moveBriefToBottom", defaultValue: "Move Brief to bottom panel")
    }

    private func dotColor(for account: AccountRecord) -> Color {
        AccountRow.deterministicColor(for: account.id)
    }
}

private struct RBToolbarFilterPopover: View {
    let menu: RBToolbarFilterMenu
    let onSelect: (ThreadFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "toolbar.filter", defaultValue: "Filter"))
                .font(.rbGeist(12, weight: .semibold))
                .foregroundStyle(Color.rbFg2)
                .padding(.horizontal, RBSpace.s2)
                .padding(.bottom, 4)

            ForEach(ThreadFilter.allCases, id: \.self) { filter in
                Button {
                    onSelect(filter)
                } label: {
                    HStack(spacing: RBSpace.s2) {
                        Text(filter.label)
                            .font(.rbGeist(13, weight: .medium))
                            .foregroundStyle(Color.rbFg1)
                        Spacer(minLength: RBSpace.s4)
                        if filter == menu.selectedFilter {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.rbAccent)
                        }
                    }
                    .frame(width: 172, alignment: .leading)
                    .padding(.horizontal, RBSpace.s2)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: filter))
            }
        }
        .padding(8)
        .background(Color.rbBgElev1)
    }

    private func accessibilityLabel(for filter: ThreadFilter) -> String {
        guard filter == menu.selectedFilter else { return filter.label }
        let suffix = String(localized: "toolbar.filter.selectedSuffix", defaultValue: ", selected")
        return "\(filter.label)\(suffix)"
    }
}

#if DEBUG
struct RBToolbarPreview: View {
    @FocusState private var focused: Bool
    var body: some View {
        RBToolbar(
            accounts: [],
            activeAccountID: nil,
            onCycleAccount: {},
            onToggleTheme: {},
            onOpenSettings: {},
            onCompose: {},
            filterMenu: RBToolbarFilterMenu(selectedFilter: .all, onSelect: { _ in }),
            searchFocused: $focused,
            searchText: .constant(""),
            onSubmitSearch: {}
        )
        .preferredColorScheme(.dark)
    }
}

#Preview("RBToolbar - Dark") {
    RBToolbarPreview()
}
#endif
