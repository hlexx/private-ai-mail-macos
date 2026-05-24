import Foundation
import GRDB
import MailProviders
import Persistence

public actor SyncSupervisor {
    private var engines: [String: MailSyncEngine] = [:]
    private let db: AppDatabase
    private let apiFactory: GmailAPIFactory

    public init(db: AppDatabase, apiFactory: @escaping GmailAPIFactory) {
        self.db = db
        self.apiFactory = apiFactory
    }

    public func start(accountId: String) async throws {
        if let existing = engines[accountId] {
            let state = await existing.state
            guard state == .degraded else { return }
            // Remove the stuck engine so we can retry bootstrap
            await existing.stop()
            engines.removeValue(forKey: accountId)
        }
        let api = try apiFactory(accountId)
        let engine = MailSyncEngine(accountId: accountId, api: api, db: db)
        engines[accountId] = engine
        await engine.bootstrap()
    }

    public func startIncremental(accountId: String) async throws {
        if engines[accountId] != nil { return }
        let api = try apiFactory(accountId)
        let engine = MailSyncEngine(accountId: accountId, api: api, db: db)
        engines[accountId] = engine

        let historyId: String? = try? db.read { db in
            try SyncStateRecord
                .filter(Column("account_id") == accountId)
                .fetchOne(db)?.historyId
        }.flatMap { $0 }
        let hasHistoryId = historyId != nil

        if hasHistoryId {
            await engine.refresh()
        } else {
            await engine.bootstrap()
        }
    }

    public func refresh(accountId: String) async throws {
        guard let engine = engines[accountId] else { return }
        await engine.refresh()
    }

    public func stop(accountId: String) async {
        guard let engine = engines[accountId] else { return }
        await engine.stop()
        engines.removeValue(forKey: accountId)
    }

    public func events(for accountId: String) async -> AsyncStream<SyncEvent>? {
        await engines[accountId]?.makeEventStream()
    }

    public func state(for accountId: String) async -> SyncState? {
        guard let engine = engines[accountId] else { return nil }
        return await engine.state
    }
}
