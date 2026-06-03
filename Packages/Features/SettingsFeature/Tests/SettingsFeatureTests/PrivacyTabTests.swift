import Persistence
import Testing
@testable import SettingsFeature

@Suite("PrivacyTab")
struct PrivacyTabTests {
    @Test func privacySurfaceContainsRequiredCopyKeys() throws {
        let gmailAccount = account(id: "gmail-1", provider: "gmail", email: "user@gmail.com")
        let outlookAccount = account(id: "outlook-1", provider: "outlook", email: "user@outlook.com")
        var states = [
            PrivacySettingsState.make(accounts: []),
            PrivacySettingsState.make(accounts: [gmailAccount]),
            PrivacySettingsState.make(accounts: [outlookAccount]),
            PrivacySettingsState.make(accounts: [gmailAccount, outlookAccount]),
        ]

        for phase in ProviderReauthorizationPhase.privacyTestCases {
            states.append(PrivacySettingsState.make(
                accounts: [gmailAccount, outlookAccount],
                reauthorizationPhases: [gmailAccount.id: phase]
            ))
        }

        let visibleKeys = Set(states.flatMap(\.copyKeys))
        let requiredKeys = Set(PrivacyCopyKey.requiredKeys)

        #expect(requiredKeys == visibleKeys)
        #expect(Set(PrivacyCopyKey.requiredKeys).count == PrivacyCopyKey.requiredKeys.count)
    }

    @Test func privacySurfaceRendersTrustStateSections() throws {
        let state = PrivacySettingsState.make(accounts: [
            account(id: "gmail-1", provider: "gmail", email: "user@gmail.com"),
        ])

        #expect(state.sections.map(\.id) == [
            .overview,
            .connectedProviders,
            .localData,
            .providerUse,
            .aiAndCloud,
            .cacheControls,
        ])

        let titles = Set(state.rows.map(\.title.defaultValue))
        #expect(titles.contains("No mailbox mirroring by default"))
        #expect(titles.contains("Gmail connected"))
        #expect(titles.contains("Local raw mail"))
        #expect(titles.contains("Local attachments"))
        #expect(titles.contains("Local drafts"))
        #expect(titles.contains("Local indexes"))
        #expect(titles.contains("Local AI artifacts"))
        #expect(titles.contains("Provider API use"))
        #expect(titles.contains("AI mode"))
        #expect(titles.contains("Cloud fallback"))
        #expect(titles.contains("Remove local cache and account"))
    }

    @Test func gmailPermissionsExposeSupportedReconsentAction() throws {
        let state = PrivacySettingsState.make(accounts: [
            account(id: "gmail-1", provider: "gmail", email: "user@gmail.com"),
        ])
        let row = try #require(state.rows.first { $0.id == "gmail-permissions-gmail-1" })

        #expect(row.detail?.defaultValue.contains("Reads mailbox content for local sync") == true)
        #expect(row.detail?.defaultValue.contains("sends messages you approve") == true)

        guard case .button(let title, let action, let isEnabled) = row.accessory else {
            Issue.record("Expected Gmail permissions to expose a re-authorization button")
            return
        }
        #expect(title.defaultValue == "Re-authorize Gmail")
        #expect(action == .reauthorize("gmail-1"))
        #expect(isEnabled)
    }

    @Test func gmailReauthorizationPhasesExposeStableCopyKeys() throws {
        let account = account(id: "gmail-1", provider: "gmail", email: "user@gmail.com")
        let cases: [(ProviderReauthorizationPhase, String, String, ExpectedReauthorizationAccessory)] = [
            (.idle, PrivacyCopyKey.gmailReauthorizeAction, "Re-authorize Gmail", .button),
            (.authorizing, PrivacyCopyKey.gmailReauthorizeProgress, "Re-authorizing...", .progress),
            (.done, PrivacyCopyKey.gmailReauthorizeDone, "Consent refreshed", .status),
            (
                .error("Network unavailable"),
                PrivacyCopyKey.gmailReauthorizeRetryAction,
                "Retry re-authorization",
                .button
            ),
        ]

        for (phase, expectedKey, expectedValue, expectedAccessory) in cases {
            let state = PrivacySettingsState.make(
                accounts: [account],
                reauthorizationPhases: [account.id: phase]
            )
            let row = try #require(state.rows.first { $0.id == "gmail-permissions-gmail-1" })

            #expect(state.copyKeys.contains(expectedKey))
            switch (expectedAccessory, row.accessory) {
            case (.button, .button(let copy, let action, let isEnabled)):
                #expect(copy.key == expectedKey)
                #expect(copy.defaultValue == expectedValue)
                #expect(action == .reauthorize(account.id))
                #expect(isEnabled)
            case (.progress, .progress(let copy)),
                 (.status, .status(let copy)):
                #expect(copy.key == expectedKey)
                #expect(copy.defaultValue == expectedValue)
            default:
                Issue.record("Expected Gmail re-authorization accessory for phase \(phase)")
            }
        }
    }

    @Test func outlookPermissionsStayHumanReadableWithoutUnsupportedReconsentControl() throws {
        let state = PrivacySettingsState.make(accounts: [
            account(id: "outlook-1", provider: "outlook", email: "user@outlook.com"),
        ])
        let row = try #require(state.rows.first { $0.id == "outlook-permissions-outlook-1" })

        #expect(row.detail?.defaultValue.contains("Reads and updates mail") == true)
        #expect(row.detail?.defaultValue.contains("sends messages you approve") == true)

        guard case .status(let status) = row.accessory else {
            Issue.record("Expected Outlook permissions to be status-only until re-consent is supported")
            return
        }
        #expect(status.defaultValue == "Re-consent unavailable in this build")
    }

    @Test func cacheControlsExposeAccountRemovalAction() throws {
        let state = PrivacySettingsState.make(accounts: [
            account(id: "gmail-1", provider: "gmail", email: "user@gmail.com"),
        ])
        let row = try #require(state.rows.first { $0.id == "cache-control-gmail-1" })

        guard case .destructiveButton(let title, let action, let isEnabled) = row.accessory else {
            Issue.record("Expected connected account cache control to remove local account data")
            return
        }
        #expect(title.defaultValue == "Remove")
        #expect(action == .removeAccount("gmail-1"))
        #expect(isEnabled)
    }

    @Test func localOnlyAIStateDoesNotExposeUnsupportedModeControls() throws {
        let state = PrivacySettingsState.make(accounts: [])
        let aiMode = try #require(state.rows.first { $0.id == "ai-mode" })
        let cloudFallback = try #require(state.rows.first { $0.id == "cloud-fallback" })

        guard case .status(let aiStatus) = aiMode.accessory else {
            Issue.record("Expected AI mode to render as status-only")
            return
        }
        guard case .status(let fallbackStatus) = cloudFallback.accessory else {
            Issue.record("Expected cloud fallback to render as status-only")
            return
        }

        #expect(aiStatus.defaultValue == "Local-only")
        #expect(fallbackStatus.defaultValue == "Off")
        #expect(!state.rows.compactMap(\.accessory).contains { accessory in
            switch accessory {
            case .button, .destructiveButton:
                return true
            default:
                return false
            }
        })
    }

    @Test func privacyRowLayoutPreservesReadableCopyWidth() {
        let rowMinimumWidth = PrivacySettingsLayout.copyColumnMinWidth
            + PrivacySettingsLayout.accessoryColumnWidth
            + 12
        #expect(rowMinimumWidth <= 640)
        #expect(PrivacySettingsLayout.accessoryColumnWidth > PrivacySettingsLayout.accessoryMaxWidth)
        #expect(PrivacySettingsLayout.detailMaxWidth >= PrivacySettingsLayout.copyColumnMinWidth)
    }

    private func account(id: String, provider: String, email: String) -> AccountRecord {
        AccountRecord(
            id: id,
            provider: provider,
            email: email,
            createdAt: 1_700_000_000
        )
    }
}

private enum ExpectedReauthorizationAccessory {
    case button
    case progress
    case status
}

private extension ProviderReauthorizationPhase {
    static let privacyTestCases: [ProviderReauthorizationPhase] = [
        .idle,
        .authorizing,
        .done,
        .error("Network unavailable"),
    ]
}
