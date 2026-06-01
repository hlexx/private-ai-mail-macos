import AppFoundation
import AuthKit
import Foundation
import GRDB
import MailProviders
import MailSync
import Observation
import Persistence

public enum AddAccountPhase: Sendable, Equatable {
    case idle
    case authorizing
    case fetchingProfile
    case bootstrapping(Double)
    case done
    case error(String)
}

public enum ProviderReauthorizationPhase: Sendable, Equatable {
    case idle
    case authorizing
    case done
    case error(String)
}

public struct AccountProviderOption: Identifiable, Sendable, Equatable {
    public enum Availability: Sendable, Equatable {
        case enabled
        case disabled(reason: String)
    }

    public let provider: AuthProvider
    public let title: String
    public let subtitle: String
    public let actionTitle: String
    public let systemImage: String
    public let availability: Availability

    public var id: String { provider.rawValue }

    public var isEnabled: Bool {
        if case .enabled = availability { return true }
        return false
    }
}

@Observable
@MainActor
public final class AccountsTabStore {
    public private(set) var accounts: [AccountRecord] = []
    public private(set) var addPhase: AddAccountPhase = .idle
    public private(set) var reauthorizationPhases: [String: ProviderReauthorizationPhase] = [:]
    public private(set) var syncStates: [String: SyncState] = [:]
    public private(set) var providerOptions: [AccountProviderOption]

    private let db: AppDatabase
    private let oauthClient: any OAuthClient
    private let tokenStore: any TokenStore
    private let syncSupervisor: SyncSupervisor
    private let localAccountCacheDeleter: @Sendable (String) throws -> Void
    private var observationTask: Task<Void, Never>?

    /// Called after a new account is fully added and sync has started.
    public var onAccountAdded: ((String) -> Void)?

    public init(
        db: AppDatabase,
        oauthClient: any OAuthClient,
        tokenStore: any TokenStore,
        syncSupervisor: SyncSupervisor,
        providerOptions: [AccountProviderOption] = AccountsTabStore.defaultProviderOptions(),
        localAccountCacheDeleter: @escaping @Sendable (String) throws -> Void = { _ in }
    ) {
        self.db = db
        self.oauthClient = oauthClient
        self.tokenStore = tokenStore
        self.syncSupervisor = syncSupervisor
        self.providerOptions = providerOptions
        self.localAccountCacheDeleter = localAccountCacheDeleter
    }

    public static func defaultProviderOptions() -> [AccountProviderOption] {
        [
            AccountProviderOption(
                provider: .gmail,
                title: "Gmail",
                subtitle: "Connect a Gmail account.",
                actionTitle: "Add Gmail account",
                systemImage: "envelope",
                availability: .enabled
            ),
            AccountProviderOption(
                provider: .outlook,
                title: "Outlook",
                subtitle: "Beta support is disabled until real account smoke tests pass.",
                actionTitle: "Add Outlook account",
                systemImage: "envelope.badge",
                availability: .disabled(reason: "Internal beta")
            ),
        ]
    }

    public func addAccount(provider: AuthProvider) {
        switch provider {
        case .gmail:
            addGmailAccount()
        case .outlook:
            addPhase = .error("Outlook support is in beta and disabled until real account smoke tests pass.")
        default:
            addPhase = .error("This mail provider is not supported yet.")
        }
    }

    public func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            guard let self else { return }
            let dbQueue = self.db.dbQueue
            let observation = ValueObservation.tracking { db in
                try AccountRecord.fetchAll(db)
            }
            do {
                for try await records in observation.values(in: dbQueue) {
                    guard !Task.isCancelled else { return }
                    self.accounts = records
                    await self.refreshSyncStates(for: records)
                }
            } catch {
                // Observation ended
            }
        }
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    public func addGmailAccount() {
        guard addPhase == .idle || addPhase == .done || isErrorPhase else { return }
        addPhase = .authorizing

        Task { [weak self] in
            guard let self else { return }
            do {
                let credential = try await self.oauthClient.authorize()
                self.addPhase = .fetchingProfile

                let email = try await self.fetchUserEmail(credential: credential)

                let existingAccount = try self.db.read { db in
                    try AccountRecord.filter(Column("provider") == "gmail" && Column("email") == email).fetchOne(db)
                }
                if existingAccount != nil {
                    self.addPhase = .error("This Gmail account is already connected.")
                    return
                }

                let accountId = UUID().uuidString

                let account = AccountRecord(
                    id: accountId,
                    provider: "gmail",
                    email: email,
                    createdAt: Int(Date().timeIntervalSince1970)
                )
                try self.tokenStore.save(credential, for: accountId)

                do {
                    try await DatabaseActor.shared.run {
                        try self.db.dbQueue.write { db in
                            try account.insert(db)
                        }
                    }
                } catch {
                    try? self.tokenStore.delete(for: accountId)
                    throw error
                }

                self.addPhase = .bootstrapping(0)
                self.observeSyncEvents(for: accountId)
                try await self.syncSupervisor.start(accountId: accountId)
                self.onAccountAdded?(accountId)
            } catch let error as AuthError where error.isCancelled {
                self.addPhase = .idle
            } catch {
                self.addPhase = .error(Self.userMessage(for: error, operation: .account, provider: "Gmail"))
            }
        }
    }

    public func removeAccount(_ accountId: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.syncSupervisor.stop(accountId: accountId)
            do {
                try self.tokenStore.delete(for: accountId)

                let deleteLocalCache = self.localAccountCacheDeleter
                try await Task.detached(priority: .utility) {
                    try deleteLocalCache(accountId)
                }.value

                try await DatabaseActor.shared.run {
                    try self.db.dbQueue.write { db in
                        _ = try AccountRecord.deleteOne(db, key: accountId)
                    }
                }
                self.syncStates.removeValue(forKey: accountId)
                self.reauthorizationPhases.removeValue(forKey: accountId)
            } catch {
                self.addPhase = .error(Self.userMessage(for: error, operation: .account))
            }
        }
    }

    public func reauthorizeAccount(_ accountId: String) {
        guard reauthorizationPhases[accountId] != .authorizing else { return }
        reauthorizationPhases[accountId] = .authorizing

        Task { [weak self] in
            guard let self else { return }
            do {
                let account = try self.db.read { db in
                    try AccountRecord.fetchOne(db, key: accountId)
                }
                guard let account else {
                    throw SettingsAccountAuthorizationError.accountNotFound
                }

                switch AuthProvider(rawValue: account.provider) {
                case .gmail:
                    let credential = try await self.oauthClient.reauthorize(
                        additionalScopes: GmailOAuthConfig.default.scopes
                    )
                    try self.tokenStore.save(credential, for: accountId)
                    self.reauthorizationPhases[accountId] = .done
                case .outlook:
                    self.reauthorizationPhases[accountId] = .error(
                        "Outlook re-consent is not available in this build."
                    )
                default:
                    self.reauthorizationPhases[accountId] = .error(
                        "This mail provider is not supported yet."
                    )
                }
            } catch {
                self.reauthorizationPhases[accountId] = .error(
                    Self.userMessage(for: error, operation: .account, provider: "Gmail")
                )
            }
        }
    }

    public func dismissError() {
        addPhase = .idle
    }

    // MARK: - Private

    private var isErrorPhase: Bool {
        if case .error = addPhase { return true }
        return false
    }

    private func fetchUserEmail(credential: TokenCredential) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("\(credential.tokenType) \(credential.accessToken)", forHTTPHeaderField: "Authorization")

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.invalidResponse
        }
        struct UserInfo: Decodable { let email: String }
        let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
        return userInfo.email
    }

    private func observeSyncEvents(for accountId: String) {
        Task { [weak self] in
            guard let self else { return }
            guard let events = await self.syncSupervisor.events(for: accountId) else { return }
            for await event in events {
                switch event {
                case .progress(let value):
                    if case .bootstrapping = self.addPhase {
                        self.addPhase = .bootstrapping(value)
                    }
                case .state(let state):
                    self.syncStates[accountId] = state
                    if state == .live, case .bootstrapping = self.addPhase {
                        self.addPhase = .done
                    }
                case .error(let syncError):
                    if case .bootstrapping = self.addPhase {
                        self.addPhase = .error(syncError.userActionableFailure.message)
                    }
                case .threadUpserted:
                    break
                }
            }
        }
    }

    private func refreshSyncStates(for records: [AccountRecord]) async {
        for record in records {
            if let state = await syncSupervisor.state(for: record.id) {
                syncStates[record.id] = state
            }
        }
    }

    private nonisolated static func userMessage(
        for error: any Error,
        operation: UserActionableFailureOperation,
        provider: String? = nil
    ) -> String {
        if let authError = error as? AuthError {
            return authError.userActionableFailure(operation: operation, provider: provider).message
        }
        if let gmailError = error as? GmailAPIError {
            return gmailError.userActionableFailure(operation: operation).message
        }
        if let graphError = error as? GraphAPIError {
            return graphError.userActionableFailure(operation: operation).message
        }
        return UserActionableFailure.coerce(error, operation: operation, provider: provider).message
    }
}

// MARK: - Helpers

extension AuthError {
    fileprivate var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

extension DatabaseActor {
    fileprivate func run<T: Sendable>(_ work: @DatabaseActor @Sendable () throws -> T) async rethrows -> T {
        try await work()
    }
}

private enum SettingsAccountAuthorizationError: LocalizedError {
    case accountNotFound

    var errorDescription: String? {
        switch self {
        case .accountNotFound:
            return "The connected account could not be found."
        }
    }
}
