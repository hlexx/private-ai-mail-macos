import AuthKit
import Persistence
import SwiftUI

public struct PrivacyTab: View {
    @Bindable var store: AccountsTabStore

    public init(store: AccountsTabStore) {
        self.store = store
    }

    public var body: some View {
        let state = PrivacySettingsState.make(
            accounts: store.accounts,
            reauthorizationPhases: store.reauthorizationPhases
        )

        Form {
            ForEach(state.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        rowView(row)
                    }
                } header: {
                    Text(section.title.defaultValue)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            store.startObserving()
        }
        .onDisappear {
            store.stopObserving()
        }
    }

    private func rowView(_ row: PrivacySettingsRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title.defaultValue)
                    .font(.body)
                if let detail = row.detail {
                    Text(detail.defaultValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            accessoryView(row.accessory)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func accessoryView(_ accessory: PrivacySettingsAccessory?) -> some View {
        switch accessory {
        case .none:
            EmptyView()
        case .status(let text):
            Text(text.defaultValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        case .progress(let text):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(text.defaultValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .button(let text, let action, let isEnabled):
            Button(text.defaultValue) {
                perform(action)
            }
            .disabled(!isEnabled)
        case .destructiveButton(let text, let action, let isEnabled):
            Button(role: .destructive) {
                perform(action)
            } label: {
                Text(text.defaultValue)
            }
            .disabled(!isEnabled)
        }
    }

    private func perform(_ action: PrivacySettingsAction) {
        switch action {
        case .reauthorize(let accountId):
            store.reauthorizeAccount(accountId)
        case .removeAccount(let accountId):
            store.removeAccount(accountId)
        }
    }
}

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
            overviewSection(),
            connectedProvidersSection(accounts: accounts),
            localDataSection(),
            providerUseSection(accounts: accounts, reauthorizationPhases: reauthorizationPhases),
            aiAndCloudSection(),
            cacheControlsSection(accounts: accounts),
        ])
    }

    private static func overviewSection() -> PrivacySettingsSection {
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

    private static func connectedProvidersSection(accounts: [AccountRecord]) -> PrivacySettingsSection {
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

    private static func localDataSection() -> PrivacySettingsSection {
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

    private static func providerUseSection(
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

    private static func aiAndCloudSection() -> PrivacySettingsSection {
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

    private static func cacheControlsSection(accounts: [AccountRecord]) -> PrivacySettingsSection {
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

    private static func reauthorizationAccessory(
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

    private static var gmailPermissionSummary: String {
        "Reads mailbox content for local sync, sends messages you approve, and reads your account email for sign-in."
    }

    private static var outlookPermissionSummary: String {
        "Reads and updates mail, sends messages you approve, keeps offline access, and reads basic profile/email for sign-in."
    }

    private static func providerDisplayName(_ provider: String) -> String {
        switch AuthProvider(rawValue: provider) {
        case .gmail:
            return "Gmail"
        case .outlook:
            return "Outlook"
        default:
            return provider.capitalized
        }
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

enum PrivacyCopyKey {
    static let overviewSectionTitle = "privacy.section.overview"
    static let noMirroringTitle = "privacy.noMirroring.title"
    static let noMirroringDetail = "privacy.noMirroring.detail"
    static let noMirroringStatus = "privacy.noMirroring.status"

    static let connectedProvidersSectionTitle = "privacy.section.connectedProviders"
    static let connectedProvidersEmptyTitle = "privacy.connectedProviders.empty.title"
    static let connectedProvidersEmptyDetail = "privacy.connectedProviders.empty.detail"
    static let connectedProvidersEmptyStatus = "privacy.connectedProviders.empty.status"
    static let connectedProviderTitle = "privacy.connectedProviders.provider.title"
    static let connectedProviderDetail = "privacy.connectedProviders.provider.detail"
    static let connectedProviderStatus = "privacy.connectedProviders.provider.status"

    static let localDataSectionTitle = "privacy.section.localData"
    static let localRawMailTitle = "privacy.localData.rawMail.title"
    static let localRawMailDetail = "privacy.localData.rawMail.detail"
    static let localAttachmentsTitle = "privacy.localData.attachments.title"
    static let localAttachmentsDetail = "privacy.localData.attachments.detail"
    static let localDraftsTitle = "privacy.localData.drafts.title"
    static let localDraftsDetail = "privacy.localData.drafts.detail"
    static let localIndexesTitle = "privacy.localData.indexes.title"
    static let localIndexesDetail = "privacy.localData.indexes.detail"
    static let localAIArtifactsTitle = "privacy.localData.aiArtifacts.title"
    static let localAIArtifactsDetail = "privacy.localData.aiArtifacts.detail"

    static let providerUseSectionTitle = "privacy.section.providerUse"
    static let providerAPIUseTitle = "privacy.providerUse.api.title"
    static let providerAPIUseDetail = "privacy.providerUse.api.detail"
    static let providerAPIUseStatus = "privacy.providerUse.api.status"
    static let gmailPermissionsTitle = "privacy.providerUse.gmail.title"
    static let gmailPermissionsDetail = "privacy.providerUse.gmail.detail"
    static let gmailPermissionsEmptyStatus = "privacy.providerUse.gmail.empty.status"
    static let gmailReauthorizeAction = "privacy.providerUse.gmail.reauthorize"
    static let gmailReauthorizeProgress = "privacy.providerUse.gmail.reauthorize.progress"
    static let gmailReauthorizeDone = "privacy.providerUse.gmail.reauthorize.done"
    static let gmailReauthorizeRetryAction = "privacy.providerUse.gmail.reauthorize.retry"
    static let outlookPermissionsTitle = "privacy.providerUse.outlook.title"
    static let outlookPermissionsDetail = "privacy.providerUse.outlook.detail"
    static let outlookPermissionsBetaStatus = "privacy.providerUse.outlook.beta.status"
    static let outlookPermissionsUnsupportedStatus = "privacy.providerUse.outlook.unsupported.status"

    static let aiAndCloudSectionTitle = "privacy.section.aiAndCloud"
    static let aiModeTitle = "privacy.ai.mode.title"
    static let aiModeDetail = "privacy.ai.mode.detail"
    static let aiModeStatus = "privacy.ai.mode.status"
    static let cloudFallbackTitle = "privacy.ai.cloudFallback.title"
    static let cloudFallbackDetail = "privacy.ai.cloudFallback.detail"
    static let cloudFallbackStatus = "privacy.ai.cloudFallback.status"

    static let cacheControlsSectionTitle = "privacy.section.cacheControls"
    static let cacheControlsEmptyTitle = "privacy.cache.empty.title"
    static let cacheControlsEmptyDetail = "privacy.cache.empty.detail"
    static let cacheControlsEmptyStatus = "privacy.cache.empty.status"
    static let cacheControlTitle = "privacy.cache.remove.title"
    static let cacheControlDetail = "privacy.cache.remove.detail"
    static let cacheControlAction = "privacy.cache.remove.action"

    static let requiredKeys: [String] = [
        noMirroringTitle,
        noMirroringDetail,
        connectedProvidersSectionTitle,
        localDataSectionTitle,
        localRawMailTitle,
        localAttachmentsTitle,
        localDraftsTitle,
        localIndexesTitle,
        localAIArtifactsTitle,
        providerUseSectionTitle,
        providerAPIUseTitle,
        gmailPermissionsTitle,
        gmailPermissionsDetail,
        outlookPermissionsTitle,
        outlookPermissionsDetail,
        aiModeTitle,
        aiModeStatus,
        cloudFallbackTitle,
        cloudFallbackStatus,
        cacheControlsSectionTitle,
        cacheControlTitle,
        cacheControlAction,
    ]
}
