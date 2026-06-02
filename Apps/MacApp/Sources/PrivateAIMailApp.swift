import ComposeFeature
import DesignSystem
import MailDomain
import Persistence
import SwiftUI

@main
struct PrivateAIMailApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private let keyboardDispatcher = KeyboardDispatcher()
    private let sparkleUpdater = SparkleUpdater()
    @State private var startup = AppStartupState.bootstrap()

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if let composition = startup.composition {
                    if composition.aiModelController.shouldShowFirstLaunchOnboarding {
                        AIOnboardingScene(modelController: composition.aiModelController)
                            .frame(minWidth: 560, minHeight: 440)
                    } else {
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
                            .onChange(of: composition.aiModelController.isAIReady) { _, ready in
                                composition.applyAIAvailability()
                                if ready {
                                    composition.briefBackgroundQueue.backfillMissing(limit: 200)
                                }
                            }
                    }
                } else if let failure = startup.failure {
                    StartupRecoveryScene(failure: failure, onRetry: retryStartup)
                        .frame(minWidth: 560, minHeight: 360)
                }
            }
            .task(id: startup.id) {
                guard let composition = startup.composition else { return }
                await composition.aiModelController.refreshInstalledStatus()
                composition.applyAIAvailability()
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
                .disabled(startup.composition == nil)
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
            if let composition = startup.composition {
                ComposeWindowView(viewModel: composition.composeViewModel)
                    .frame(minWidth: 600, minHeight: 480)
                    .rbTheme()
            } else if let failure = startup.failure {
                StartupRecoveryScene(failure: failure, onRetry: retryStartup)
                    .frame(minWidth: 560, minHeight: 360)
                    .rbTheme()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 560)

        Settings {
            if let composition = startup.composition {
                SettingsScene(composition: composition)
                    .rbTheme()
            } else if let failure = startup.failure {
                StartupRecoveryScene(failure: failure, onRetry: retryStartup)
                    .rbTheme()
            }
        }
    }

    private func prepareComposeViewModel() {
        guard let composition = startup.composition else { return }
        let vm = composition.composeViewModel
        vm.reset()
        let accounts = (try? composition.db.read { db in try AccountRecord.fetchAll(db) }) ?? []
        vm.accounts = accounts.map {
            AccountInfo(
                id: $0.id,
                email: $0.email,
                displayName: $0.displayName,
                provider: MailProviderIdentifier(rawValue: $0.provider)
            )
        }
        if let activeID = composition.activeAccountID ?? accounts.first?.id {
            vm.selectedAccountID = activeID
            vm.selectedAccountEmail = accounts.first(where: { $0.id == activeID })?.email
        }
    }

    private func retryStartup() {
        startup = AppStartupState.bootstrap()
    }

    private func configureMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: {
                $0.identifier?.rawValue.contains("main") == true
                || $0.title.contains("Re:Box")
            }) else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
        }
    }
}
