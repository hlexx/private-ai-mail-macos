import Persistence
import Testing
@testable import SettingsFeature

@Suite("PrivacyTab")
struct PrivacyTabTests {
    @Test func privacySurfaceContainsRequiredCopyKeys() throws {
        let state = PrivacySettingsState.make(accounts: [
            account(id: "gmail-1", provider: "gmail", email: "user@gmail.com"),
            account(id: "outlook-1", provider: "outlook", email: "user@outlook.com"),
        ])
        let copyKeys = Set(state.copyKeys)

        for key in PrivacyCopyKey.requiredKeys {
            #expect(copyKeys.contains(key), "Missing required privacy copy key: \(key)")
        }
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
        #expect(!state.controls.contains { accessory in
            switch accessory {
            case .button, .destructiveButton:
                return true
            default:
                return false
            }
        })
    }

    @Test func privacyRowLayoutPreservesReadableCopyWidth() {
        #expect(PrivacySettingsLayout.detailMaxWidth == 520)
        #expect(PrivacySettingsLayout.accessoryMaxWidth == 180)
        #expect(PrivacySettingsLayout.copyColumnMinWidth >= 360)
        #expect(PrivacySettingsLayout.accessoryColumnWidth > PrivacySettingsLayout.accessoryMaxWidth)
        #expect(PrivacySettingsLayout.detailMaxWidth > PrivacySettingsLayout.accessoryColumnWidth * 2)
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
