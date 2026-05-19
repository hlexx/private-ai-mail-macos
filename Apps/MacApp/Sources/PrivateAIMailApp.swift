import ComposeFeature
import DesignSystem
import Persistence
import SwiftUI

@main
struct PrivateAIMailApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private let composition = CompositionRoot()
    private let keyboardDispatcher = KeyboardDispatcher()
    private let sparkleUpdater = SparkleUpdater()
    @State private var setupComplete = false

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if setupComplete {
                    MainScene(composition: composition, keyboardDispatcher: keyboardDispatcher)
                        .frame(minWidth: 980, minHeight: 720)
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
            CommandMenu(String(localized: "menu.mail", defaultValue: "Mail")) {
                Button(String(localized: "menu.mail.reply", defaultValue: "Reply")) {
                    keyboardDispatcher.handle(.reply)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(String(localized: "menu.mail.replyAll", defaultValue: "Reply All")) {
                    keyboardDispatcher.handle(.replyAll)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button(String(localized: "menu.mail.forward", defaultValue: "Forward")) {
                    keyboardDispatcher.handle(.forward)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button(String(localized: "menu.mail.archive", defaultValue: "Archive")) {
                    keyboardDispatcher.handle(.archive)
                }

                Button(String(localized: "menu.mail.star", defaultValue: "Star / Unstar")) {
                    keyboardDispatcher.handle(.star)
                }

                Button(String(localized: "menu.mail.trash", defaultValue: "Move to Trash")) {
                    keyboardDispatcher.handle(.trash)
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Button(String(localized: "menu.mail.markRead", defaultValue: "Mark as Read")) {
                    keyboardDispatcher.handle(.markRead)
                }

                Button(String(localized: "menu.mail.markUnread", defaultValue: "Mark as Unread")) {
                    keyboardDispatcher.handle(.markUnread)
                }

                Divider()

                Button(String(localized: "menu.refresh", defaultValue: "Refresh")) {
                    keyboardDispatcher.handle(.refresh)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button(String(localized: "menu.keyboardShortcuts", defaultValue: "Keyboard Shortcuts")) {
                    keyboardDispatcher.showKeyboardHelp.toggle()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
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
