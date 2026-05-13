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

    @AppStorage("rb-theme") private var themeRaw: String = RBTheme.system.rawValue
    @State private var searchText = ""

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
                .frame(width: 240, alignment: .leading)

            trailingSection
        }
        .frame(height: 56)
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
            SearchField(text: $searchText, onCommit: onOpenActionSheet)
                .frame(maxWidth: 480)

            Spacer(minLength: RBSpace.s2)

            HStack(spacing: 4) {
                RBIconButton(
                    systemName: "line.3.horizontal.decrease",
                    accessibilityLabel: String(localized: "toolbar.filter", defaultValue: "Filter")
                ) {}

                RBIconButton(
                    systemName: theme == .light ? "moon" : "sun.max",
                    accessibilityLabel: String(
                        localized: "toolbar.theme",
                        defaultValue: theme == .light ? "Switch to dark" : "Switch to light"
                    ),
                    action: onToggleTheme
                )

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

    private func dotColor(for account: AccountRecord) -> Color {
        let hash = abs(account.id.hashValue)
        let colors: [Color] = [.rbCobalt500, .rbViolet500, .rbCitron500, .rbToneJade400, .rbToneCoral400, .rbToneIce400]
        return colors[hash % colors.count]
    }
}

#if DEBUG
#Preview("RBToolbar - Dark") {
    RBToolbar(
        accounts: [],
        activeAccountID: nil,
        onCycleAccount: {},
        onToggleTheme: {},
        onOpenSettings: {},
        onCompose: {},
        onOpenActionSheet: {}
    )
    .preferredColorScheme(.dark)
}
#endif
