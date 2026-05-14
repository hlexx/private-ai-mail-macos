import AIRuntime
import AuthKit
import BriefFeature
import InboxFeature
import MailProviders
import MailSync
import Persistence
import SettingsFeature
import SwiftUI
import ThreadFeature

@MainActor @Observable
final class CompositionRoot {
    let db: AppDatabase
    let modelManager: ModelManager
    let inboxStore: InboxStore
    let threadStore: ThreadStore
    let briefStore: BriefStore
    let accountsTabStore: AccountsTabStore
    let syncSupervisor: SyncSupervisor

    var activeAccountID: String?
    var showActionSheet = false
    var showCompose = false

    private let oauthClient: any OAuthClient
    private let tokenStore: any TokenStore

    init() {
        let path = Self.defaultDBPath()
        // swiftlint:disable:next force_try
        self.db = try! AppDatabase.openSync(at: path)
        self.modelManager = ModelManager()
        self.inboxStore = InboxStore(db: db)
        self.threadStore = ThreadStore(db: db)
        self.briefStore = BriefStore()

        let tokenStore: any TokenStore = KeychainTokenStore()
        self.tokenStore = tokenStore

        let oauthClient: any OAuthClient = GmailOAuthClient()
        self.oauthClient = oauthClient

        let apiFactory: @Sendable (String) -> any GmailAPI = { [tokenStore, oauthClient] accountId in
            let credential = (try? tokenStore.load(for: accountId)) ?? TokenCredential(
                accessToken: "",
                refreshToken: "",
                expiresAt: .distantPast
            )
            return GmailAPIClient(
                accountId: accountId,
                credential: credential,
                oauthClient: oauthClient,
                tokenStore: tokenStore
            )
        }

        self.syncSupervisor = SyncSupervisor(db: db, apiFactory: apiFactory)

        self.accountsTabStore = AccountsTabStore(
            db: db,
            oauthClient: oauthClient,
            tokenStore: tokenStore,
            syncSupervisor: syncSupervisor
        )
    }

    private static func defaultDBPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("PrivateAIMail")
            .appendingPathComponent("db.sqlite")
            .path
    }

    func resumeExistingAccounts() {
        #if DEBUG
        // Populate the DB with seven synthetic threads from the Re:Box
        // handoff so the UI has something realistic to render before a real
        // Gmail account is connected. No-op when the DB already has accounts.
        DevSeeder.seedIfEmpty(db: db)
        #endif

        Task {
            let accounts = try? db.read { db in try AccountRecord.fetchAll(db) }
            for account in accounts ?? [] {
                await syncSupervisor.startIncremental(accountId: account.id)
            }
        }
    }

    func refreshAccount(_ accountId: String) {
        Task {
            await syncSupervisor.refresh(accountId: accountId)
        }
    }

    func refreshAllAccounts() {
        Task {
            let accounts = try? db.read { db in try AccountRecord.fetchAll(db) }
            for account in accounts ?? [] {
                await syncSupervisor.refresh(accountId: account.id)
            }
        }
    }

    func cycleActiveAccount(accounts: [AccountRecord]) {
        guard !accounts.isEmpty else { return }
        if let current = activeAccountID,
           let idx = accounts.firstIndex(where: { $0.id == current }) {
            activeAccountID = accounts[(idx + 1) % accounts.count].id
        } else {
            activeAccountID = accounts.first?.id
        }
    }
}
