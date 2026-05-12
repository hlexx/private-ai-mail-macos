import SwiftUI

@main
struct PrivateAIMailApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let composition = CompositionRoot()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainScene(composition: composition)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.compose.new", defaultValue: "New Message")) {
                    // Compose window — wired in later iteration.
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        Settings {
            SettingsScene(composition: composition)
        }
    }
}
