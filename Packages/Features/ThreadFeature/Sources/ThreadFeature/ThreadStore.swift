import Foundation
import Observation
import Persistence
import GRDB

public struct MessageRow: Identifiable, Sendable {
    public let id: String
    public let threadId: String
    public let fromAddr: String
    public let sentAt: Date
    public let snippet: String
    public let bodyText: String

    public init(record: MessageRecord) {
        self.id = record.id
        self.threadId = record.threadId
        self.fromAddr = record.fromAddr ?? "(unknown)"
        self.sentAt = Date(timeIntervalSince1970: TimeInterval(record.sentAt))
        self.snippet = record.snippet ?? ""
        self.bodyText = record.bodyText ?? record.snippet ?? ""
    }
}

@Observable
@MainActor
public final class ThreadStore {
    public private(set) var messages: [MessageRow] = []

    private let db: AppDatabase
    private var observationTask: Task<Void, Never>?

    public init(db: AppDatabase) {
        self.db = db
    }

    public func observe(threadId: String, accountId: String) {
        observationTask?.cancel()
        observationTask = Task { [db] in
            let observation = ValueObservation.tracking { db in
                try MessageRecord
                    .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                    .order(Column("sent_at").asc)
                    .fetchAll(db)
            }
            do {
                for try await records in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled else { return }
                    self.messages = records.map(MessageRow.init)
                }
            } catch {
                // Observation ended
            }
        }
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        messages = []
    }
}
