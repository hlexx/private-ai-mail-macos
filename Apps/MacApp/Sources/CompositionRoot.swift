import AIKit
import AIRuntime
import AuthKit
import BriefFeature
import ComposeFeature
import InboxFeature
import MailProviders
import MailSync
import Persistence
import SettingsFeature
import SwiftUI
import ThreadFeature
import TranslationFeature

struct ToastState: Equatable {
    let id = UUID()
    let message: String
    let undoAction: UndoAction?

    enum UndoAction: Equatable {
        case unarchive(threadId: String, accountId: String)
        case star(threadId: String, accountId: String)
        case unstar(threadId: String, accountId: String)
        case untrash(threadId: String, accountId: String)
    }
}

@MainActor @Observable
final class CompositionRoot {
    let db: AppDatabase
    let modelManager: ModelManager
    let aiService: any AIService
    let inboxStore: InboxStore
    let threadStore: ThreadStore
    let briefStore: BriefStore
    let briefBackgroundQueue: BriefBackgroundQueue
    let replyStore: ReplyStore
    let accountsTabStore: AccountsTabStore
    let syncSupervisor: SyncSupervisor
    let mailMutator: MailMutator
    let labelReconciler: LabelReconciler
    let translationStore: TranslationStore

    var activeAccountID: String?
    var toastMessage: ToastState? {
        didSet { toastDismissTask?.cancel(); toastDismissTask = nil }
    }
    var showActionSheet = false
    var showCompose = false
    let composeViewModel: ComposeViewModel

    private let oauthClient: any OAuthClient
    private let tokenStore: any TokenStore
    private let apiFactory: @Sendable (String) -> any GmailAPI

    init() {
        let path = Self.defaultDBPath()
        // swiftlint:disable:next force_try
        self.db = try! AppDatabase.openSync(at: path)
        self.modelManager = ModelManager()
        self.aiService = ThreadBriefService.live(modelManager: modelManager)
        self.inboxStore = InboxStore(db: db)
        self.threadStore = ThreadStore(db: db)
        self.briefStore = BriefStore(aiService: aiService, db: db)
        self.briefBackgroundQueue = BriefBackgroundQueue(aiService: aiService, db: db)
        self.replyStore = ReplyStore(aiService: aiService, db: db)

        let tokenStore: any TokenStore = KeychainTokenStore()
        self.tokenStore = tokenStore

        let oauthClient: any OAuthClient = GmailOAuthClient()
        self.oauthClient = oauthClient

        self.apiFactory = { [tokenStore, oauthClient] accountId in
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
        let mutationAPIFactory: @Sendable (String) throws -> any GmailAPI = { [tokenStore, oauthClient] accountId in
            guard let credential = try tokenStore.load(for: accountId),
                  !credential.accessToken.isEmpty || !credential.refreshToken.isEmpty else {
                throw MailMutationError.missingCredential(accountId: accountId)
            }
            return GmailAPIClient(
                accountId: accountId,
                credential: credential,
                oauthClient: oauthClient,
                tokenStore: tokenStore
            )
        }

        self.syncSupervisor = SyncSupervisor(db: db, apiFactory: apiFactory)
        self.mailMutator = MailMutator(db: db, apiFactory: mutationAPIFactory)
        self.labelReconciler = LabelReconciler(db: db, apiFactory: apiFactory)
        self.translationStore = TranslationStore(db: db)

        let capturedFactory = apiFactory
        let capturedDB = db
        let capturedOAuth = oauthClient
        let capturedTokenStore = tokenStore
        self.composeViewModel = ComposeViewModel(
            composeServiceFactory: { accountId in
                LiveComposeService(api: capturedFactory(accountId), db: capturedDB)
            },
            reauthorizeHandler: { @MainActor accountId in
                let newCredential = try await capturedOAuth.reauthorize(
                    additionalScopes: ["https://www.googleapis.com/auth/gmail.send"]
                )
                try capturedTokenStore.save(newCredential, for: accountId)
            }
        )

        self.accountsTabStore = AccountsTabStore(
            db: db,
            oauthClient: oauthClient,
            tokenStore: tokenStore,
            syncSupervisor: syncSupervisor
        )

        self.accountsTabStore.onAccountAdded = { [weak self] accountId in
            self?.subscribeSyncEvents(accountId: accountId)
        }
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

    var toastDismissTask: Task<Void, Never>?
    private var syncEventTasks: [String: Task<Void, Never>] = [:]
    private var debounceTimers: [String: Task<Void, Never>] = [:]

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
                subscribeSyncEvents(accountId: account.id)
            }

            // Backfill briefs for threads that don't have one yet
            briefBackgroundQueue.backfillMissing(limit: 200)
        }
    }

    private func subscribeSyncEvents(accountId: String) {
        guard syncEventTasks[accountId] == nil else { return }
        syncEventTasks[accountId] = Task { [weak self] in
            guard let events = await self?.syncSupervisor.events(for: accountId) else { return }
            for await event in events {
                guard let self, !Task.isCancelled else { break }
                if case .threadUpserted(let threadId) = event {
                    self.debouncedEnqueue(accountId: accountId, threadId: threadId)
                }
            }
            // Clean up so re-subscribing works if the account is re-added
            self?.syncEventTasks.removeValue(forKey: accountId)
        }
    }

    private func debouncedEnqueue(accountId: String, threadId: String) {
        let key = "\(accountId):\(threadId)"
        debounceTimers[key]?.cancel()
        debounceTimers[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.briefBackgroundQueue.enqueue(accountId: accountId, threadId: threadId)
            self.debounceTimers.removeValue(forKey: key)
        }
    }

    func refreshAccount(_ accountId: String) {
        Task {
            await syncSupervisor.refresh(accountId: accountId)
        }
    }

    func makeComposeService(accountId: String) -> any ComposeService {
        LiveComposeService(api: apiFactory(accountId), db: db)
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
