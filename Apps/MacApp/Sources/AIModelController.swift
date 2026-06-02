import AIRuntime
import Foundation
import Observation

@MainActor
@Observable
final class AIModelController {
    private enum Keys {
        static let onboardingCompleted = "pam.ai.onboardingCompleted"
        static let enabled = "pam.ai.enabled"
    }

    let modelManager: ModelManager

    var hasCompletedOnboarding: Bool
    var isAIEnabled: Bool
    var isModelInstalled: Bool
    var isInstalling = false
    var downloadFraction: Double = 0
    var bytesDownloaded: Int64 = 0
    var totalBytes: Int64 = 0
    var installErrorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var installTask: Task<Void, Never>?

    init(
        modelManager: ModelManager,
        defaults: UserDefaults = .standard,
        isModelInstalled: Bool = false
    ) {
        self.modelManager = modelManager
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboardingCompleted)
        self.isAIEnabled = defaults.bool(forKey: Keys.enabled)
        self.isModelInstalled = isModelInstalled
    }

    var shouldShowFirstLaunchOnboarding: Bool {
        !hasCompletedOnboarding && !isModelInstalled
    }

    var isAIReady: Bool {
        isAIEnabled && isModelInstalled
    }

    var byteCountLabel: String {
        guard totalBytes > 0 else { return "Preparing download..." }
        let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(downloaded) / \(total)"
    }

    func refreshInstalledStatus() async {
        let installedURL = await modelManager.installedURL()
        isModelInstalled = installedURL != nil
        if isModelInstalled && !hasCompletedOnboarding {
            completeOnboarding(aiEnabled: true)
        }
    }

    func enableAI() {
        completeOnboarding(aiEnabled: true)
        installErrorMessage = nil
    }

    func disableAI() {
        cancelInstallIfNeeded()
        completeOnboarding(aiEnabled: false)
    }

    func continueWithoutAI() {
        disableAI()
    }

    func startInstall(completeOnboardingImmediately: Bool = true) {
        guard !isInstalling else { return }
        if completeOnboardingImmediately {
            completeOnboarding(aiEnabled: true)
        } else {
            setAIEnabled(true)
        }
        installErrorMessage = nil
        isInstalling = true

        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                if await self.modelManager.installedURL() == nil {
                    _ = try await self.modelManager.install { fraction, downloaded, total in
                        Task { @MainActor [weak self] in
                            self?.downloadFraction = fraction
                            self?.bytesDownloaded = downloaded
                            self?.totalBytes = total
                        }
                    }
                }
                self.isModelInstalled = true
                self.isInstalling = false
                self.downloadFraction = 1
                self.installErrorMessage = nil
                self.completeOnboarding(aiEnabled: true)
            } catch is CancellationError {
                self.isInstalling = false
            } catch {
                self.isInstalling = false
                self.installErrorMessage = Self.userMessage(for: error)
            }
        }
    }

    private func completeOnboarding(aiEnabled: Bool) {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Keys.onboardingCompleted)
        setAIEnabled(aiEnabled)
    }

    private func setAIEnabled(_ enabled: Bool) {
        isAIEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
    }

    private func cancelInstallIfNeeded() {
        installTask?.cancel()
        installTask = nil
        isInstalling = false
    }

    private nonisolated static func userMessage(for error: any Error) -> String {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(urlError.code) {
            return "No internet - required for the one-time model download."
        }
        return "Download failed: \(error.localizedDescription)"
    }
}
