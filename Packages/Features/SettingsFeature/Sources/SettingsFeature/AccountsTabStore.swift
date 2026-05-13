import Foundation
import Observation
import AuthKit
import Persistence
import MailSync
import MailProviders
import GRDB

public enum AddAccountPhase: Sendable, Equatable {
    case idle
    case authorizing
    case fetchingProfile
    case bootstrapping(Double)
    case done
    case error(String)
}

@Observable
@MainActor
public final class AccountsTabStore {
    public private(set) var accounts: [AccountRecord] = []
    public private(set) var addPhase: AddAccountPhase = .idle
    public private(set) var syncStates: [String: SyncState] = [:]

    private let db: AppDatabase
    private let oauthClient: any OAuthClient
    private let tokenStore: any TokenStore
    private let syncSupervisor: SyncSupervisor
    private let apiFactory: @Sendable (String) -> any GmailAPI
    private var observationTask: Task<Void, Never>?

    public init(
        db: AppDatabase,
        oauthClient: any OAuthClient,
        tokenStore: any TokenStore,
        syncSupervisor: SyncSupervisor,
        apiFactory: @escaping @Sendable (String) -> any GmailAPI
    ) {
        self.db = db
        self.oauthClient = oauthClient
        self.tokenStore = tokenStore
        self.syncSupervisor = syncSupervisor
        self.apiFactory = apiFactory
    }

    public func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            guard let self else { return }
            let observation = ValueObservation.tracking { db in
                try AccountRecord.fetchAll(db)
            }
            do {
                for try await records in observation.values(in: self.db.dbQueue) {
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
                let accountId = UUID().uuidString

                try self.tokenStore.save(credential, for: accountId)

                let account = AccountRecord(
                    id: accountId,
                    provider: "gmail",
                    email: email,
                    createdAt: Int(Date().timeIntervalSince1970 * 1000)
                )
                try await DatabaseActor.shared.run {
                    try self.db.dbQueue.write { db in
                        try account.insert(db)
                    }
                }

                self.addPhase = .bootstrapping(0)
                await self.syncSupervisor.start(accountId: accountId)
                self.observeSyncEvents(for: accountId)
            } catch let error as AuthError where error.isCancelled {
                self.addPhase = .idle
            } catch {
                self.addPhase = .error(error.localizedDescription)
            }
        }
    }

    public func removeAccount(_ accountId: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.syncSupervisor.stop(accountId: accountId)
            do {
                try await DatabaseActor.shared.run {
                    try self.db.dbQueue.write { db in
                        _ = try AccountRecord.deleteOne(db, key: accountId)
                    }
                }
                try? self.tokenStore.delete(for: accountId)
                self.syncStates.removeValue(forKey: accountId)
            } catch {
                // Deletion failed — account will reappear on next observation cycle
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
                        self.addPhase = .error(syncError.localizedDescription)
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
