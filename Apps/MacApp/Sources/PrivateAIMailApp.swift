import SwiftUI

@main
struct PrivateAIMailApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let composition = CompositionRoot()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainScene(composition: composition)
                .frame(minWidth: 1000, minHeight: 640)
                .task { composition.resumeExistingAccounts() }
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
            CommandGroup(after: .toolbar) {
                Button(String(localized: "menu.refresh", defaultValue: "Refresh")) {
                    refreshCurrentAccount()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsScene(composition: composition)
        }
    }

    private func refreshCurrentAccount() {
        let store = composition.inboxStore
        if let selected = store.selectedThreadID,
           let thread = store.threads.first(where: { $0.id == selected }) {
            composition.refreshAccount(thread.accountId)
        } else {
            composition.refreshAllAccounts()
        }
    }
}
