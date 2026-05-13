import DesignSystem
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
                .rbTheme()
                .onAppear { configureMainWindow() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.compose.new", defaultValue: "New Message")) {
                    composition.showCompose = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
                Button(String(localized: "menu.refresh", defaultValue: "Refresh")) {
                    refreshCurrentAccount()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
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

    private func configureMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: {
                $0.identifier?.rawValue.contains("main") == true
                || $0.title.contains("Private AI Mail")
                || $0.contentView?.subviews.isEmpty == false
            }) else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
        }
    }
}
