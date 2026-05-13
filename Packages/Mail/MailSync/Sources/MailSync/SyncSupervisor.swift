import Foundation
import MailProviders
import Persistence

public actor SyncSupervisor {
    private var engines: [String: MailSyncEngine] = [:]
    private let db: AppDatabase
    private let apiFactory: @Sendable (String) -> any GmailAPI

    public init(db: AppDatabase, apiFactory: @escaping @Sendable (String) -> any GmailAPI) {
        self.db = db
        self.apiFactory = apiFactory
    }

    public func start(accountId: String) async {
        if engines[accountId] != nil { return }
        let api = apiFactory(accountId)
        let engine = MailSyncEngine(accountId: accountId, api: api, db: db)
        engines[accountId] = engine
        await engine.bootstrap()
    }

    public func refresh(accountId: String) async {
        guard let engine = engines[accountId] else { return }
        await engine.refresh()
    }

    public func stop(accountId: String) async {
        guard let engine = engines[accountId] else { return }
        await engine.stop()
        engines.removeValue(forKey: accountId)
    }

    public func events(for accountId: String) -> AsyncStream<SyncEvent>? {
        engines[accountId]?.events
    }

    public func state(for accountId: String) async -> SyncState? {
        guard let engine = engines[accountId] else { return nil }
        return await engine.state
    }
}
