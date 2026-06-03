import AuthKit
import Persistence

struct PrivacySettingsState: Equatable, Sendable {
    let sections: [PrivacySettingsSection]

    var rows: [PrivacySettingsRow] {
        sections.flatMap(\.rows)
    }

    var copyKeys: [String] {
        var keys = sections.map(\.title.key)
        for row in rows {
            keys.append(row.title.key)
            if let detail = row.detail {
                keys.append(detail.key)
            }
            keys.append(contentsOf: row.accessory?.copyKeys ?? [])
        }
        return keys
    }

    var controls: [PrivacySettingsAccessory] {
        rows.compactMap(\.accessory)
    }

    static func make(
        accounts: [AccountRecord],
        reauthorizationPhases: [String: ProviderReauthorizationPhase] = [:]
    ) -> PrivacySettingsState {
        PrivacySettingsState(sections: [
            makePrivacyOverviewSection(),
            makePrivacyConnectedProvidersSection(accounts: accounts),
            makePrivacyLocalDataSection(),
            makePrivacyProviderUseSection(accounts: accounts, reauthorizationPhases: reauthorizationPhases),
            makePrivacyAIAndCloudSection(),
            makePrivacyCacheControlsSection(accounts: accounts),
        ])
    }
}

private func makePrivacyOverviewSection() -> PrivacySettingsSection {
    PrivacySettingsSection(
        id: .overview,
        title: PrivacyCopy(PrivacyCopyKey.overviewSectionTitle, "Privacy model"),
        rows: [
            PrivacySettingsRow(
                id: "no-mailbox-mirroring",
                title: PrivacyCopy(PrivacyCopyKey.noMirroringTitle, "No mailbox mirroring by default"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.noMirroringDetail,
                    "Mailbox bodies, drafts, indexes, attachment bytes, and AI artifacts are not copied to the app cloud."
                ),
                accessory: .status(PrivacyCopy(PrivacyCopyKey.noMirroringStatus, "Default"))
            ),
        ]
    )
}

private func makePrivacyConnectedProvidersSection(accounts: [AccountRecord]) -> PrivacySettingsSection {
    let rows: [PrivacySettingsRow]
    if accounts.isEmpty {
        rows = [
            PrivacySettingsRow(
                id: "connected-provider-empty",
                title: PrivacyCopy(PrivacyCopyKey.connectedProvidersEmptyTitle, "No connected providers"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.connectedProvidersEmptyDetail,
                    "Connect Gmail from Accounts to start local sync. Outlook remains disabled until beta smoke tests pass."
                ),
                accessory: .status(PrivacyCopy(PrivacyCopyKey.connectedProvidersEmptyStatus, "Local only"))
            ),
        ]
    } else {
        rows = accounts.map { account in
            PrivacySettingsRow(
                id: "connected-provider-\(account.id)",
                title: PrivacyCopy(
                    PrivacyCopyKey.connectedProviderTitle,
                    "\(providerDisplayName(account.provider)) connected"
                ),
                detail: PrivacyCopy(
                    PrivacyCopyKey.connectedProviderDetail,
                    "\(account.email) syncs through \(providerDisplayName(account.provider)) provider APIs into local storage."
                ),
                accessory: .status(PrivacyCopy(PrivacyCopyKey.connectedProviderStatus, "Connected"))
            )
        }
    }

    return PrivacySettingsSection(
        id: .connectedProviders,
        title: PrivacyCopy(PrivacyCopyKey.connectedProvidersSectionTitle, "Connected providers"),
        rows: rows
    )
}

private func makePrivacyLocalDataSection() -> PrivacySettingsSection {
    PrivacySettingsSection(
        id: .localData,
        title: PrivacyCopy(PrivacyCopyKey.localDataSectionTitle, "Local data classes"),
        rows: [
            PrivacySettingsRow(
                id: "local-raw-mail",
                title: PrivacyCopy(PrivacyCopyKey.localRawMailTitle, "Local raw mail"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.localRawMailDetail,
                    "Bodies, HTML, snippets, headers, labels, and read/star/archive state stay in the local database."
                )
            ),
            PrivacySettingsRow(
                id: "local-attachments",
                title: PrivacyCopy(PrivacyCopyKey.localAttachmentsTitle, "Local attachments"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.localAttachmentsDetail,
                    "Attachment metadata and fetched bytes stay in local persistence and cache paths."
                )
            ),
            PrivacySettingsRow(
                id: "local-drafts",
                title: PrivacyCopy(PrivacyCopyKey.localDraftsTitle, "Local drafts"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.localDraftsDetail,
                    "Draft bodies and queued outgoing snapshots stay local until you send or cancel them."
                )
            ),
            PrivacySettingsRow(
                id: "local-indexes",
                title: PrivacyCopy(PrivacyCopyKey.localIndexesTitle, "Local indexes"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.localIndexesDetail,
                    "Search tokens, result references, and local ranking hints are derived and stored on this Mac."
                )
            ),
            PrivacySettingsRow(
                id: "local-ai-artifacts",
                title: PrivacyCopy(PrivacyCopyKey.localAIArtifactsTitle, "Local AI artifacts"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.localAIArtifactsDetail,
                    "Prompt inputs, model outputs, summaries, evidence, and AI cache records remain on device in local-only mode."
                )
            ),
        ]
    )
}

private func makePrivacyProviderUseSection(
    accounts: [AccountRecord],
    reauthorizationPhases: [String: ProviderReauthorizationPhase]
) -> PrivacySettingsSection {
    let gmailAccounts = accounts.filter { AuthProvider(rawValue: $0.provider) == .gmail }
    let outlookAccounts = accounts.filter { AuthProvider(rawValue: $0.provider) == .outlook }

    var rows: [PrivacySettingsRow] = [
        PrivacySettingsRow(
            id: "provider-api-use",
            title: PrivacyCopy(PrivacyCopyKey.providerAPIUseTitle, "Provider API use"),
            detail: PrivacyCopy(
                PrivacyCopyKey.providerAPIUseDetail,
                "Provider calls are limited to sync, re-consent, attachment fetch, user-requested mutation, and send."
            ),
            accessory: .status(PrivacyCopy(PrivacyCopyKey.providerAPIUseStatus, "Gmail / Microsoft Graph"))
        ),
    ]

    if gmailAccounts.isEmpty {
        rows.append(PrivacySettingsRow(
            id: "gmail-permissions-empty",
            title: PrivacyCopy(PrivacyCopyKey.gmailPermissionsTitle, "Gmail permissions"),
            detail: PrivacyCopy(PrivacyCopyKey.gmailPermissionsDetail, gmailPermissionSummary),
            accessory: .status(PrivacyCopy(PrivacyCopyKey.gmailPermissionsEmptyStatus, "No connected Gmail account"))
        ))
    } else {
        rows.append(contentsOf: gmailAccounts.map { account in
            PrivacySettingsRow(
                id: "gmail-permissions-\(account.id)",
                title: PrivacyCopy(PrivacyCopyKey.gmailPermissionsTitle, "Gmail permissions"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.gmailPermissionsDetail,
                    "\(gmailPermissionSummary) Account: \(account.email)."
                ),
                accessory: reauthorizationAccessory(
                    accountId: account.id,
                    provider: .gmail,
                    phase: reauthorizationPhases[account.id] ?? .idle
                )
            )
        })
    }

    if outlookAccounts.isEmpty {
        rows.append(PrivacySettingsRow(
            id: "outlook-permissions-empty",
            title: PrivacyCopy(PrivacyCopyKey.outlookPermissionsTitle, "Outlook permissions"),
            detail: PrivacyCopy(PrivacyCopyKey.outlookPermissionsDetail, outlookPermissionSummary),
            accessory: .status(PrivacyCopy(PrivacyCopyKey.outlookPermissionsBetaStatus, "Beta disabled"))
        ))
    } else {
        rows.append(contentsOf: outlookAccounts.map { account in
            PrivacySettingsRow(
                id: "outlook-permissions-\(account.id)",
                title: PrivacyCopy(PrivacyCopyKey.outlookPermissionsTitle, "Outlook permissions"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.outlookPermissionsDetail,
                    "\(outlookPermissionSummary) Account: \(account.email)."
                ),
                accessory: .status(PrivacyCopy(
                    PrivacyCopyKey.outlookPermissionsUnsupportedStatus,
                    "Re-consent unavailable in this build"
                ))
            )
        })
    }

    return PrivacySettingsSection(
        id: .providerUse,
        title: PrivacyCopy(PrivacyCopyKey.providerUseSectionTitle, "Provider API and permissions"),
        rows: rows
    )
}

private func makePrivacyAIAndCloudSection() -> PrivacySettingsSection {
    PrivacySettingsSection(
        id: .aiAndCloud,
        title: PrivacyCopy(PrivacyCopyKey.aiAndCloudSectionTitle, "AI and cloud fallback"),
        rows: [
            PrivacySettingsRow(
                id: "ai-mode",
                title: PrivacyCopy(PrivacyCopyKey.aiModeTitle, "AI mode"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.aiModeDetail,
                    "Briefs, reply drafts, attachment summaries, and translations use implemented on-device runtimes."
                ),
                accessory: .status(PrivacyCopy(PrivacyCopyKey.aiModeStatus, "Local-only"))
            ),
            PrivacySettingsRow(
                id: "cloud-fallback",
                title: PrivacyCopy(PrivacyCopyKey.cloudFallbackTitle, "Cloud fallback"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.cloudFallbackDetail,
                    "Disabled. No mailbox content, drafts, indexes, attachment bytes, prompts, or AI outputs are sent to app cloud fallback."
                ),
                accessory: .status(PrivacyCopy(PrivacyCopyKey.cloudFallbackStatus, "Off"))
            ),
        ]
    )
}

private func makePrivacyCacheControlsSection(accounts: [AccountRecord]) -> PrivacySettingsSection {
    let rows: [PrivacySettingsRow]
    if accounts.isEmpty {
        rows = [
            PrivacySettingsRow(
                id: "cache-controls-empty",
                title: PrivacyCopy(PrivacyCopyKey.cacheControlsEmptyTitle, "No local account cache"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.cacheControlsEmptyDetail,
                    "Connect an account before local cache removal controls are available."
                ),
                accessory: .status(PrivacyCopy(PrivacyCopyKey.cacheControlsEmptyStatus, "Nothing to remove"))
            ),
        ]
    } else {
        rows = accounts.map { account in
            PrivacySettingsRow(
                id: "cache-control-\(account.id)",
                title: PrivacyCopy(PrivacyCopyKey.cacheControlTitle, "Remove local cache and account"),
                detail: PrivacyCopy(
                    PrivacyCopyKey.cacheControlDetail,
                    "Stops sync for \(account.email), deletes the stored credential, and removes local rows tied to this account through the persistence cascade."
                ),
                accessory: .destructiveButton(
                    PrivacyCopy(PrivacyCopyKey.cacheControlAction, "Remove"),
                    action: .removeAccount(account.id),
                    isEnabled: true
                )
            )
        }
    }

    return PrivacySettingsSection(
        id: .cacheControls,
        title: PrivacyCopy(PrivacyCopyKey.cacheControlsSectionTitle, "Local cache controls"),
        rows: rows
    )
}

private func reauthorizationAccessory(
    accountId: String,
    provider: AuthProvider,
    phase: ProviderReauthorizationPhase
) -> PrivacySettingsAccessory {
    switch phase {
    case .idle:
        return .button(
            PrivacyCopy(PrivacyCopyKey.gmailReauthorizeAction, "Re-authorize Gmail"),
            action: .reauthorize(accountId),
            isEnabled: provider == .gmail
        )
    case .authorizing:
        return .progress(PrivacyCopy(PrivacyCopyKey.gmailReauthorizeProgress, "Re-authorizing..."))
    case .done:
        return .status(PrivacyCopy(PrivacyCopyKey.gmailReauthorizeDone, "Consent refreshed"))
    case .error:
        return .button(
            PrivacyCopy(PrivacyCopyKey.gmailReauthorizeRetryAction, "Retry re-authorization"),
            action: .reauthorize(accountId),
            isEnabled: provider == .gmail
        )
    }
}

private let gmailPermissionSummary =
    "Reads mailbox content for local sync, sends messages you approve, and reads your account email for sign-in."

private let outlookPermissionSummary =
    "Reads and updates mail, sends messages you approve, keeps offline access, and reads basic profile/email for sign-in."

private func providerDisplayName(_ provider: String) -> String {
    switch AuthProvider(rawValue: provider) {
    case .gmail:
        return "Gmail"
    case .outlook:
        return "Outlook"
    default:
        return provider.capitalized
    }
}

struct PrivacySettingsSection: Identifiable, Equatable, Sendable {
    let id: PrivacySettingsSectionID
    let title: PrivacyCopy
    let rows: [PrivacySettingsRow]
}

enum PrivacySettingsSectionID: String, Sendable {
    case overview
    case connectedProviders
    case localData
    case providerUse
    case aiAndCloud
    case cacheControls
}

struct PrivacySettingsRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: PrivacyCopy
    let detail: PrivacyCopy?
    let accessory: PrivacySettingsAccessory?

    init(
        id: String,
        title: PrivacyCopy,
        detail: PrivacyCopy? = nil,
        accessory: PrivacySettingsAccessory? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.accessory = accessory
    }
}

enum PrivacySettingsAccessory: Equatable, Sendable {
    case status(PrivacyCopy)
    case progress(PrivacyCopy)
    case button(PrivacyCopy, action: PrivacySettingsAction, isEnabled: Bool)
    case destructiveButton(PrivacyCopy, action: PrivacySettingsAction, isEnabled: Bool)

    var copyKeys: [String] {
        switch self {
        case .status(let copy), .progress(let copy):
            return [copy.key]
        case .button(let copy, _, _),
             .destructiveButton(let copy, _, _):
            return [copy.key]
        }
    }
}

enum PrivacySettingsAction: Equatable, Sendable {
    case reauthorize(String)
    case removeAccount(String)
}

struct PrivacyCopy: Equatable, Sendable {
    let key: String
    let defaultValue: String

    init(_ key: String, _ defaultValue: String) {
        self.key = key
        self.defaultValue = defaultValue
    }
}
