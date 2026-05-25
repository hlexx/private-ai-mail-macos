import AuthKit
import Foundation
import Testing

@testable import PrivateAIMail

@Suite("LabelReconcileCoordinator")
@MainActor
struct LabelReconcileCoordinatorTests {
    private let flagKey = "pam.needsLabelReconcile"

    @Test("Skips accounts without credentials and clears migration flag")
    func skipsAccountsWithoutCredentials() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: flagKey)

        let recorder = ReconcileRecorder()
        var toasts: [ToastState] = []

        let coordinator = LabelReconcileCoordinator(
            defaults: defaults,
            hasCredential: { _ in false },
            reconcile: { accountId in
                await recorder.record(accountId)
            }
        )

        coordinator.runIfNeeded(
            accountIds: ["demo-work-gmail", "demo-personal-gmail"],
            showToast: { toasts.append($0) },
            clearToastIfCurrent: { _ in }
        )

        #expect(await recorder.values().isEmpty)
        #expect(defaults.bool(forKey: flagKey) == false)
        #expect(toasts.isEmpty)
    }

    @Test("Reconciles only accounts with credentials and clears flag on success")
    func reconcilesOnlyCredentialedAccounts() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: flagKey)

        let recorder = ReconcileRecorder()
        var toasts: [ToastState] = []
        var clearedToastIDs: [UUID] = []
        let credentialedAccounts: Set<String> = ["real-gmail"]

        let coordinator = LabelReconcileCoordinator(
            defaults: defaults,
            hasCredential: { accountId in credentialedAccounts.contains(accountId) },
            reconcile: { accountId in
                await recorder.record(accountId)
            }
        )

        coordinator.runIfNeeded(
            accountIds: ["demo-work-gmail", "real-gmail", "demo-personal-gmail"],
            showToast: { toasts.append($0) },
            clearToastIfCurrent: { clearedToastIDs.append($0) }
        )

        try await waitUntil {
            await recorder.values() == ["real-gmail"] && !clearedToastIDs.isEmpty
        }

        #expect(defaults.bool(forKey: flagKey) == false)
        #expect(toasts.map(\.kind) == [.progress])
        #expect(clearedToastIDs.first == toasts.first?.id)
    }

    @Test("Auth failures keep migration flag and show reconnect error")
    func authFailureKeepsFlagAndShowsReconnectError() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: flagKey)

        var toasts: [ToastState] = []

        let coordinator = LabelReconcileCoordinator(
            defaults: defaults,
            hasCredential: { _ in true },
            reconcile: { _ in
                throw AuthError.invalidResponse
            }
        )

        coordinator.runIfNeeded(
            accountIds: ["real-gmail"],
            showToast: { toasts.append($0) },
            clearToastIfCurrent: { _ in }
        )

        try await waitUntil {
            toasts.contains(where: { $0.kind == .error })
        }

        #expect(defaults.bool(forKey: flagKey) == true)
        #expect(toasts.last?.kind == .error)
        #expect(toasts.last?.message == "Reconnect Gmail to finish refreshing labels.")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "LabelReconcileCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func waitUntil(
        attempts: Int = 50,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for condition")
    }
}

private actor ReconcileRecorder {
    private var accountIds: [String] = []

    func record(_ accountId: String) {
        accountIds.append(accountId)
    }

    func values() -> [String] {
        accountIds
    }
}
