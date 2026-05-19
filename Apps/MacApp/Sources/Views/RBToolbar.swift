import DesignSystem
import Persistence
import SwiftUI

struct RBToolbar: View {

    let accounts: [AccountRecord]
    let activeAccountID: String?
    let onCycleAccount: () -> Void
    let onToggleTheme: () -> Void
    let onOpenSettings: () -> Void
    let onCompose: () -> Void
    let onOpenActionSheet: () -> Void
    var onToggleSidebar: (() -> Void)?
    var onToggleBrief: (() -> Void)?
    var sidebarWidth: CGFloat = RBLayout.sidebarWidth
    var sidebarCollapsed: Bool = false
    var searchFocused: FocusState<Bool>.Binding

    @State private var searchText: String = ""

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
            Spacer()
                .frame(width: 68)

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
            SearchField(text: $searchText, isFocused: searchFocused, onCommit: { onOpenActionSheet() })
                .frame(maxWidth: 480)

            Spacer(minLength: RBSpace.s2)

            HStack(spacing: 4) {
                RBIconButton(
                    systemName: "line.3.horizontal.decrease",
                    accessibilityLabel: String(localized: "toolbar.filter", defaultValue: "Filter")
                ) {}

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

    private func dotColor(for account: AccountRecord) -> Color {
        AccountRow.deterministicColor(for: account.id)
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
            onOpenActionSheet: {},
            searchFocused: $focused
        )
        .preferredColorScheme(.dark)
    }
}

#Preview("RBToolbar - Dark") {
    RBToolbarPreview()
}
#endif
