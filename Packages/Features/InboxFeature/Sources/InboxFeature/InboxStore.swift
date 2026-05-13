import Foundation
import Observation
import Persistence
import GRDB

public struct ThreadRow: Identifiable, Sendable, Hashable {
    public let id: String
    public let accountId: String
    public let subject: String
    public let snippet: String
    public let lastMessageAt: Date
    public let messageCount: Int
    public let hasUnread: Bool

    public init(record: ThreadRecord) {
        self.id = record.id
        self.accountId = record.accountId
        self.subject = record.subject ?? "(no subject)"
        self.snippet = record.snippet ?? ""
        self.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(record.lastMessageAt))
        self.messageCount = record.messageCount
        self.hasUnread = record.hasUnread != 0
    }
}

@Observable
@MainActor
public final class InboxStore {
    public private(set) var threads: [ThreadRow] = []
    public var selectedThreadID: String?

    private let db: AppDatabase
    private var observationTask: Task<Void, Never>?

    public init(db: AppDatabase) {
        self.db = db
    }

    public func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [db] in
            let observation = ValueObservation.tracking { db in
                try ThreadRecord
                    .order(Column("last_message_at").desc)
                    .fetchAll(db)
            }
            do {
                for try await records in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled else { return }
                    self.threads = records.map(ThreadRow.init)
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
}
