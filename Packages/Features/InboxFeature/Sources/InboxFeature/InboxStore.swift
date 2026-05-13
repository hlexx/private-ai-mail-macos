import Foundation
import GRDB
import Observation
import Persistence

public enum ThreadFilter: String, CaseIterable, Sendable {
    case all
    case needsReply = "reply"
    case hasDeadline = "due"
    case hasAttachment = "att"
    case aiHandled = "ai"

    public var label: String {
        switch self {
        case .all: return String(localized: "filter.all", defaultValue: "All")
        case .needsReply: return String(localized: "filter.needsReply", defaultValue: "Needs reply")
        case .hasDeadline: return String(localized: "filter.hasDeadline", defaultValue: "Has deadline")
        case .hasAttachment: return String(localized: "filter.attachments", defaultValue: "Attachments")
        case .aiHandled: return String(localized: "filter.aiHandled", defaultValue: "AI handled")
        }
    }
}

public struct ThreadRow: Identifiable, Sendable, Hashable {
    public let id: String
    public let accountId: String
    public let subject: String
    public let snippet: String
    public let lastMessageAt: Date
    public let messageCount: Int
    public let hasUnread: Bool
    public let senderName: String
    public let senderAddr: String
    public let attachmentCount: Int

    public init(record: ThreadRecord, latestFromAddr: String? = nil, attachmentCount: Int = 0) {
        self.id = record.id
        self.accountId = record.accountId
        self.subject = record.subject ?? "(no subject)"
        self.snippet = record.snippet ?? ""
        self.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(record.lastMessageAt))
        self.messageCount = record.messageCount
        self.hasUnread = record.hasUnread != 0
        self.attachmentCount = attachmentCount

        let addr = latestFromAddr ?? ""
        self.senderAddr = addr
        self.senderName = Self.extractName(from: addr)
    }

    static func extractName(from addr: String) -> String {
        let trimmed = addr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "?" }
        // "Display Name <email@example.com>" → "Display Name"
        if let angleBracket = trimmed.firstIndex(of: "<") {
            let name = trimmed[trimmed.startIndex..<angleBracket]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
        }
        // Bare email → use local part
        if let at = trimmed.firstIndex(of: "@") {
            return String(trimmed[trimmed.startIndex..<at])
        }
        return trimmed
    }
}

@Observable
@MainActor
public final class InboxStore {
    public private(set) var threads: [ThreadRow] = []
    public var selectedThreadID: String?
    public var filter: ThreadFilter = .all

    public var filteredThreads: [ThreadRow] {
        guard filter != .all else { return threads }
        return threads.filter { thread in
            switch filter {
            case .all: return true
            case .needsReply: return false // TODO(§15-step-4): drive from AIKit brief
            case .hasDeadline: return false // TODO(§15-step-4): drive from AIKit brief
            case .hasAttachment: return thread.attachmentCount > 0
            case .aiHandled: return false // TODO(§15-step-4): drive from AIKit brief
            }
        }
    }

    public var needsReplyCount: Int {
        // TODO(§15-step-4): drive from AIKit brief
        0
    }

    private let db: AppDatabase
    private var observationTask: Task<Void, Never>?

    public init(db: AppDatabase) {
        self.db = db
    }

    public func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db in
                let threads = try ThreadRecord
                    .order(Column("last_message_at").desc)
                    .fetchAll(db)

                return try threads.map { thread -> (ThreadRecord, String?, Int) in
                    let latestFrom = try String.fetchOne(
                        db,
                        sql: """
                            SELECT from_addr FROM message
                            WHERE thread_id = ?
                            ORDER BY sent_at DESC LIMIT 1
                            """,
                        arguments: [thread.id]
                    )
                    let attCount = try Int.fetchOne(
                        db,
                        sql: """
                            SELECT COUNT(*) FROM attachment
                            WHERE message_id IN (
                                SELECT id FROM message WHERE thread_id = ?
                            )
                            """,
                        arguments: [thread.id]
                    ) ?? 0
                    return (thread, latestFrom, attCount)
                }
            }
            do {
                for try await records in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled, let self else { return }
                    self.threads = records.map { thread, fromAddr, attCount in
                        ThreadRow(record: thread, latestFromAddr: fromAddr, attachmentCount: attCount)
                    }
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
