import SwiftUI
import SettingsFeature
import DesignSystem

struct SettingsScene: View {

    let composition: CompositionRoot

    var body: some View {
        TabView {
            placeholder(
                title: String(localized: "settings.tab.accounts", defaultValue: "Accounts"),
                systemImage: "person.crop.circle"
            )
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

            placeholder(
                title: String(localized: "settings.tab.ai", defaultValue: "AI"),
                systemImage: "sparkles"
            )
            .tabItem {
                Label(
                    String(localized: "settings.tab.ai", defaultValue: "AI"),
                    systemImage: "sparkles"
                )
            }
        }
        .frame(width: 520, height: 360)
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
