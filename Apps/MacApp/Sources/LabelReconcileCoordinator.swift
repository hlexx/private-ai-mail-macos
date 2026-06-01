import AppFoundation
import AuthKit
import Foundation
import MailProviders
import MailSync

@MainActor
final class LabelReconcileCoordinator {
    private static let flagKey = "pam.needsLabelReconcile"

    private let defaults: UserDefaults
    private let hasCredential: @Sendable (String) throws -> Bool
    private let reconcile: @Sendable (String) async throws -> Void
    private var isRunning = false

    convenience init(
        reconciler: LabelReconciler,
        tokenStore: any TokenStore,
        defaults: UserDefaults = .standard
    ) {
        self.init(
            defaults: defaults,
            hasCredential: { accountId in
                try tokenStore.load(for: accountId) != nil
            },
            reconcile: { accountId in
                try await reconciler.reconcileInbox(accountId: accountId)
            }
        )
    }

    init(
        defaults: UserDefaults = .standard,
        hasCredential: @escaping @Sendable (String) throws -> Bool,
        reconcile: @escaping @Sendable (String) async throws -> Void
    ) {
        self.defaults = defaults
        self.hasCredential = hasCredential
        self.reconcile = reconcile
    }

    func runIfNeeded(
        accountIds: [String],
        showToast: @escaping (ToastState) -> Void,
        clearToastIfCurrent: @escaping (UUID) -> Void
    ) {
        guard !accountIds.isEmpty,
              defaults.bool(forKey: Self.flagKey),
              !isRunning else { return }

        let eligibility = resolveEligibility(accountIds)
        if !eligibility.skipped.isEmpty {
            Self.logReconcile(
                status: "skipped_missing_credentials",
                count: eligibility.skipped.count
            )
        }

        guard !eligibility.eligible.isEmpty else {
            if eligibility.failures.isEmpty {
                defaults.set(false, forKey: Self.flagKey)
                Self.logReconcile(status: "skipped_no_credentials")
                return
            }
            showToast(ToastState(message: failureMessage(for: eligibility.failures), undoAction: nil, kind: .error))
            return
        }

        isRunning = true
        Self.logReconcile(status: "started", count: eligibility.eligible.count)

        let toast = ToastState(
            message: String(
                localized: "labels.reconciling",
                defaultValue: "Refreshing labels from Gmail…"
            ),
            undoAction: nil,
            kind: .progress
        )
        showToast(toast)

        Task { [weak self] in
            guard let self else { return }
            var failures = eligibility.failures

            for accountId in eligibility.eligible {
                do {
                    try await reconcile(accountId)
                    Self.logReconcile(status: "succeeded", accountId: accountId)
                } catch {
                    failures.append((accountId, error))
                    Self.logReconcile(
                        status: "failed",
                        accountId: accountId,
                        severity: .error,
                        errorCategory: Self.errorCategory(error)
                    )
                }
            }

            if failures.isEmpty {
                defaults.set(false, forKey: Self.flagKey)
                clearToastIfCurrent(toast.id)
                Self.logReconcile(status: "completed", count: eligibility.eligible.count)
            } else {
                showToast(ToastState(message: failureMessage(for: failures), undoAction: nil, kind: .error))
            }

            isRunning = false
        }
    }

    private func resolveEligibility(_ accountIds: [String]) -> (
        eligible: [String],
        skipped: [String],
        failures: [(String, any Error)]
    ) {
        var eligible: [String] = []
        var skipped: [String] = []
        var failures: [(String, any Error)] = []

        for accountId in accountIds {
            do {
                if try hasCredential(accountId) {
                    eligible.append(accountId)
                } else {
                    skipped.append(accountId)
                }
            } catch {
                failures.append((accountId, error))
            }
        }

        return (eligible, skipped, failures)
    }

    private func failureMessage(for failures: [(String, any Error)]) -> String {
        if failures.contains(where: { requiresReconnect($0.1) }) {
            return String(
                localized: "labels.reconnectRequired",
                defaultValue: "Reconnect Gmail to finish refreshing labels."
            )
        }
        return String(
            localized: "labels.reconcileFailed",
            defaultValue: "Label refresh failed. The app will retry next launch."
        )
    }

    private func requiresReconnect(_ error: any Error) -> Bool {
        if let error = error as? GmailAPIError {
            switch error {
            case .unauthorized, .insufficientScope:
                return true
            default:
                return false
            }
        }

        if let error = error as? AuthError {
            switch error {
            case .denied, .invalidResponse, .missingRefreshToken:
                return true
            default:
                return false
            }
        }

        return false
    }

    private nonisolated static func logReconcile(
        status: String,
        accountId: String? = nil,
        count: Int? = nil,
        severity: PrivacyObservabilitySeverity = .info,
        errorCategory: String? = nil
    ) {
        var fields: [PrivacyObservabilityField: String] = [
            .provider: "gmail",
            .operation: "label_reconcile",
            .status: status
        ]
        if let accountId, !accountId.isEmpty {
            fields[.accountID] = accountId
        }
        if let count {
            fields[.count] = "\(count)"
        }
        if let errorCategory {
            fields[.errorCategory] = errorCategory
        }
        PrivacyObservability.log(
            PrivacyObservabilityEvent(category: .sync, name: "sync.label_reconcile", fields: fields),
            severity: severity
        )
    }

    private nonisolated static func errorCategory(_ error: any Error) -> String {
        if let error = error as? GmailAPIError {
            return error.sharedCategory.rawValue
        }
        if let error = error as? AuthError {
            switch error {
            case .cancelled:
                return "cancelled"
            case .denied:
                return "authExpired"
            case .network:
                return "offline"
            case .decode, .invalidResponse:
                return "invalidResponse"
            case .keychain, .missingRefreshToken, .missingCredential, .missingProviderCredential:
                return "missingCredential"
            case .invalidConfiguration:
                return "unsupportedOperation"
            }
        }
        return String(describing: type(of: error))
    }
}
