import DesignSystem
import SettingsFeature
import SwiftUI

struct SettingsScene: View {

    let composition: CompositionRoot

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label(
                        String(localized: "settings.tab.general", defaultValue: "General"),
                        systemImage: "gearshape"
                    )
                }

            AccountsTab(store: composition.accountsTabStore)
                .tabItem {
                    Label(
                        String(localized: "settings.tab.accounts", defaultValue: "Accounts"),
                        systemImage: "person.crop.circle"
                    )
                }

            placeholder(
                title: String(localized: "settings.tab.privacy", defaultValue: "Privacy"),
                systemImage: "lock.shield"
            )
            .tabItem {
                Label(
                    String(localized: "settings.tab.privacy", defaultValue: "Privacy"),
                    systemImage: "lock.shield"
                )
            }

            AITab(queue: composition.briefBackgroundQueue)
            .tabItem {
                Label(
                    String(localized: "settings.tab.ai", defaultValue: "AI"),
                    systemImage: "sparkles"
                )
            }
        }
        .frame(width: RBLayout.settingsWidth, height: RBLayout.settingsHeight)
    }

    private func placeholder(title: String, systemImage: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(String(
                localized: "settings.placeholder.description",
                defaultValue: "Coming soon."
            ))
        )
    }
}
