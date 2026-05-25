import AIKit
import AIRuntime
import AttachmentKit
import AttachmentRAG
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
    let attachmentSummaryOrchestrator: AttachmentSummaryOrchestrator
    let attachmentSummaryStore: AttachmentSummaryStore

    var activeAccountID: String?
    var toastMessage: ToastState? {
        didSet { toastDismissTask?.cancel(); toastDismissTask = nil }
    }
    var showActionSheet = false
    var showCompose = false
    let composeViewModel: ComposeViewModel

    private let labelReconcileCoordinator: LabelReconcileCoordinator
    private let oauthClient: any OAuthClient
    private let tokenStore: any TokenStore
    private let apiFactory: GmailAPIFactory

    init() throws {
        let path = Self.defaultDBPath()
        self.db = try AppDatabase.openSync(at: path)
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
            guard let credential = try tokenStore.load(for: accountId) else {
                throw AuthError.missingCredential(accountID: accountId)
            }
            return GmailAPIClient(
                accountId: accountId,
                credential: credential,
                oauthClient: oauthClient,
                tokenStore: tokenStore
            )
        }

        self.syncSupervisor = SyncSupervisor(db: db, apiFactory: apiFactory)
        self.mailMutator = MailMutator(db: db, apiFactory: apiFactory)
        self.labelReconciler = LabelReconciler(db: db, apiFactory: apiFactory)
        self.labelReconcileCoordinator = LabelReconcileCoordinator(
            reconciler: labelReconciler,
            tokenStore: tokenStore
        )
        self.translationStore = TranslationStore(db: db)
        self.attachmentSummaryOrchestrator = AttachmentSummaryOrchestrator(
            db: db,
            byteStore: AttachmentByteStore(baseURL: AttachmentByteStore.defaultBaseURL()),
            aiService: aiService,
            byteProvider: GmailAttachmentByteProvider(apiFactory: apiFactory)
        )
        self.attachmentSummaryStore = AttachmentSummaryStore(orchestrator: attachmentSummaryOrchestrator)

        let capturedFactory = apiFactory
        let capturedDB = db
        let capturedOAuth = oauthClient
        let capturedTokenStore = tokenStore
        self.composeViewModel = ComposeViewModel(
            composeServiceFactory: { accountId in
                LiveComposeService(api: try capturedFactory(accountId), db: capturedDB)
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

    nonisolated static func defaultDBPath() -> String {
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
        guard !Self.isRunningTests else { return }

        #if DEBUG
        // Populate the DB with seven synthetic threads from the Re:Box
        // handoff so the UI has something realistic to render before a real
        // Gmail account is connected. No-op when the DB already has accounts.
        DevSeeder.seedIfEmpty(db: db)
        #endif

        Task {
            let accounts = try? db.read { db in try AccountRecord.fetchAll(db) }
            for account in accounts ?? [] {
                do {
                    try await syncSupervisor.startIncremental(accountId: account.id)
                    subscribeSyncEvents(accountId: account.id)
                } catch {
                    showErrorToast("Sync start failed: \(describe(error))")
                }
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
            do {
                try await syncSupervisor.refresh(accountId: accountId)
            } catch {
                showErrorToast("Refresh failed: \(describe(error))")
            }
        }
    }

    func makeComposeService(accountId: String) throws -> any ComposeService {
        LiveComposeService(api: try apiFactory(accountId), db: db)
    }

    func refreshAllAccounts() {
        Task {
            let accounts = try? db.read { db in try AccountRecord.fetchAll(db) }
            for account in accounts ?? [] {
                do {
                    try await syncSupervisor.refresh(accountId: account.id)
                } catch {
                    showErrorToast("Refresh failed: \(describe(error))")
                }
            }
        }
    }

    func reconcileLabelsIfNeeded(accountIds: [String]) {
        guard !Self.isRunningTests else { return }

        labelReconcileCoordinator.runIfNeeded(
            accountIds: accountIds,
            showToast: { [weak self] toast in
                self?.toastMessage = toast
            },
            clearToastIfCurrent: { [weak self] toastID in
                if self?.toastMessage?.id == toastID {
                    self?.toastMessage = nil
                }
            }
        )
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

    private func showErrorToast(_ message: String) {
        toastMessage = ToastState(message: message, undoAction: nil, kind: .error)
    }

    private func describe(_ error: any Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }

    nonisolated private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private struct GmailAttachmentByteProvider: AttachmentByteProvider {
    let apiFactory: GmailAPIFactory

    func fetchAttachmentData(accountId: String, messageId: String, attachmentId: String) async throws -> Data {
        let api = try apiFactory(accountId)
        return try await api.getAttachmentData(messageId: messageId, attachmentId: attachmentId)
    }
}
