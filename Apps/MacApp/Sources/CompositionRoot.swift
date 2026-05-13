import Foundation
import Persistence
import MailSync
import MailProviders
import AuthKit
import InboxFeature
import ThreadFeature
import SettingsFeature

@MainActor
final class CompositionRoot {
    let db: AppDatabase
    let inboxStore: InboxStore
    let threadStore: ThreadStore
    let accountsTabStore: AccountsTabStore
    let syncSupervisor: SyncSupervisor

    private let oauthClient: any OAuthClient
    private let tokenStore: any TokenStore

    init() {
        let path = Self.defaultDBPath()
        // swiftlint:disable:next force_try
        self.db = try! AppDatabase.openSync(at: path)
        self.inboxStore = InboxStore(db: db)
        self.threadStore = ThreadStore(db: db)

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
            syncSupervisor: syncSupervisor,
            apiFactory: apiFactory
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

    func refreshAccount(_ accountId: String) {
        Task {
            await syncSupervisor.refresh(accountId: accountId)
        }
    }
}
