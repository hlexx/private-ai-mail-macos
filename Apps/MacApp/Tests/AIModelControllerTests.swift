import AIRuntime
import Foundation
import Testing

@testable import PrivateAIMail

@Suite("AIModelController")
@MainActor
struct AIModelControllerTests {

    @Test func defaultsStartWithOnboardingIncompleteAndAIOff() {
        let (controller, defaults, suiteName) = makeController()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(controller.hasCompletedOnboarding == false)
        #expect(controller.isAIEnabled == false)
        #expect(controller.shouldShowFirstLaunchOnboarding == true)
        #expect(controller.isAIReady == false)
    }

    @Test func continueWithoutAIPersistsCompletedDisabledChoice() {
        let (controller, defaults, suiteName) = makeController()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        controller.continueWithoutAI()

        #expect(controller.hasCompletedOnboarding == true)
        #expect(controller.isAIEnabled == false)
        #expect(controller.shouldShowFirstLaunchOnboarding == false)
        #expect(defaults.bool(forKey: "pam.ai.onboardingCompleted") == true)
        #expect(defaults.bool(forKey: "pam.ai.enabled") == false)
    }

    @Test func enableAIPersistsCompletedEnabledChoice() {
        let (controller, defaults, suiteName) = makeController()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        controller.enableAI()

        #expect(controller.hasCompletedOnboarding == true)
        #expect(controller.isAIEnabled == true)
        #expect(defaults.bool(forKey: "pam.ai.onboardingCompleted") == true)
        #expect(defaults.bool(forKey: "pam.ai.enabled") == true)
    }

    @Test func installedModelSuppressesFirstLaunchOnboarding() {
        let (controller, defaults, suiteName) = makeController(isModelInstalled: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(controller.shouldShowFirstLaunchOnboarding == false)
    }

    private func makeController(
        isModelInstalled: Bool = false
    ) -> (AIModelController, UserDefaults, String) {
        let suiteName = "AIModelControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = ModelManager(modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()))
        let controller = AIModelController(
            modelManager: manager,
            defaults: defaults,
            isModelInstalled: isModelInstalled
        )
        return (controller, defaults, suiteName)
    }
}
