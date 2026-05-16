import ComposeFeature
import DesignSystem
import Persistence
import SwiftUI

@main
struct PrivateAIMailApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private let composition = CompositionRoot()
    private let sparkleUpdater = SparkleUpdater()
    @State private var setupComplete = false

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if setupComplete {
                    MainScene(composition: composition)
                        .frame(minWidth: 1000, minHeight: 640)
                        .task { composition.resumeExistingAccounts() }
                        .onAppear { configureMainWindow() }
                        .onChange(of: composition.showCompose) { _, show in
                            if show {
                                openWindow(id: "compose")
                                composition.showCompose = false
                            }
                        }
                } else {
                    ModelSetupScene(
                        modelManager: composition.modelManager,
                        onComplete: { setupComplete = true }
                    )
                    .frame(minWidth: 480, minHeight: 360)
                }
            }
            .task {
                let installed = await composition.modelManager.installedURL()
                if installed != nil {
                    setupComplete = true
                }
            }
            .rbTheme()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.compose.new", defaultValue: "New Message")) {
                    prepareComposeViewModel()
                    openWindow(id: "compose")
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }
            CommandGroup(after: .toolbar) {
                Button(String(localized: "menu.refresh", defaultValue: "Refresh")) {
                    refreshCurrentAccount()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        WindowGroup(id: "compose") {
            ComposeWindowView(viewModel: composition.composeViewModel)
            .frame(minWidth: 600, minHeight: 480)
            .rbTheme()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 560)

        Settings {
            SettingsScene(composition: composition)
                .rbTheme()
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

    private func prepareComposeViewModel() {
        let vm = composition.composeViewModel
        vm.reset()
        let accounts = (try? composition.db.read { db in try AccountRecord.fetchAll(db) }) ?? []
        vm.accounts = accounts.map { AccountInfo(id: $0.id, email: $0.email, displayName: $0.displayName) }
        if let activeID = composition.activeAccountID ?? accounts.first?.id {
            vm.selectedAccountID = activeID
            vm.selectedAccountEmail = accounts.first(where: { $0.id == activeID })?.email
        }
    }

    private func configureMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: {
                $0.identifier?.rawValue.contains("main") == true
                || $0.title.contains("Private AI Mail")
            }) else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
        }
    }
}
