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
        if let angleBracket = trimmed.firstIndex(of: "<") {
            let name = trimmed[trimmed.startIndex..<angleBracket]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
        }
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
    public var filter: ThreadFilter = .all {
        didSet { if oldValue != filter { startObserving() } }
    }

    public var selection: SidebarSelection = .default {
        didSet { if oldValue != selection { startObserving() } }
    }

    public private(set) var folderCounts: [FolderID: Int] = [:]

    public var filteredThreads: [ThreadRow] {
        threads
    }

    public var needsReplyCount: Int {
        folderCounts[.needsReply] ?? 0
    }

    // Legacy compat
    public var activeFolder: String {
        get {
            if case .folder(let fid) = selection { return fid.rawValue }
            return "inbox"
        }
        set {
            if let fid = FolderID(rawValue: newValue) {
                selection = .folder(fid)
            }
        }
    }

    private let db: AppDatabase
    private var observationTask: Task<Void, Never>?
    private var countsTask: Task<Void, Never>?

    public init(db: AppDatabase) {
        self.db = db
    }

    public func setSelection(_ sel: SidebarSelection) {
        selection = sel
    }

    public func startObserving() {
        observationTask?.cancel()
        let currentSelection = selection
        let currentFilter = filter
        observationTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db in
                try Self.queryThreads(db: db, selection: currentSelection, filter: currentFilter)
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
        startCountsObservation()
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        countsTask?.cancel()
        countsTask = nil
    }

    // MARK: - Folder counts observation

    private func startCountsObservation() {
        countsTask?.cancel()
        countsTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db -> [FolderID: Int] in
                var counts: [FolderID: Int] = [:]

                // Inbox count
                let inboxCount = try Int.fetchOne(db, sql: """
                    SELECT COUNT(DISTINCT tl.thread_id) FROM thread_label tl WHERE tl.label_id = 'INBOX'
                    """) ?? 0
                counts[.inbox] = inboxCount

                // Starred count
                let starredCount = try Int.fetchOne(db, sql: """
                    SELECT COUNT(DISTINCT tl.thread_id) FROM thread_label tl WHERE tl.label_id = 'STARRED'
                    """) ?? 0
                counts[.starred] = starredCount

                // Sent count
                let sentCount = try Int.fetchOne(db, sql: """
                    SELECT COUNT(DISTINCT tl.thread_id) FROM thread_label tl WHERE tl.label_id = 'SENT'
                    """) ?? 0
                counts[.sent] = sentCount

                // Archive count (threads not in INBOX/TRASH/SPAM/SENT/DRAFT)
                let archiveCount = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM thread t
                    WHERE t.id NOT IN (
                        SELECT thread_id FROM thread_label
                        WHERE label_id IN ('INBOX','TRASH','SPAM','SENT','DRAFT')
                    )
                    """) ?? 0
                counts[.archive] = archiveCount

                // Attachments count
                let attCount = try Int.fetchOne(db, sql: """
                    SELECT COUNT(DISTINCT m.thread_id) FROM message m
                    JOIN attachment a ON a.message_id = m.id
                    """) ?? 0
                counts[.attachments] = attCount

                return counts
            }
            do {
                for try await newCounts in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled, let self else { return }
                    self.folderCounts = newCounts
                }
            } catch {
                // Observation ended
            }
        }
    }

    // MARK: - Query building

    private nonisolated static func queryThreads(
        db: Database,
        selection: SidebarSelection,
        filter: ThreadFilter
    ) throws -> [(ThreadRecord, String?, Int)] {
        var conditions: [String] = []
        var arguments: [DatabaseValueConvertible] = []

        switch selection {
        case .folder(let folderID):
            switch folderID {
            case .inbox:
                conditions.append("""
                    t.id IN (SELECT thread_id FROM thread_label WHERE label_id = ?)
                    """)
                arguments.append("INBOX")
            case .starred:
                conditions.append("""
                    t.id IN (SELECT thread_id FROM thread_label WHERE label_id = ?)
                    """)
                arguments.append("STARRED")
            case .sent:
                conditions.append("""
                    t.id IN (SELECT thread_id FROM thread_label WHERE label_id = ?)
                    """)
                arguments.append("SENT")
            case .archive:
                conditions.append("""
                    t.id NOT IN (
                        SELECT thread_id FROM thread_label
                        WHERE label_id IN ('INBOX','TRASH','SPAM','SENT','DRAFT')
                    )
                    """)
            case .attachments:
                conditions.append("""
                    EXISTS (SELECT 1 FROM message m2 JOIN attachment a ON a.message_id = m2.id WHERE m2.thread_id = t.id)
                    """)
            case .needsReply, .hasDeadline, .logged:
                // Brief-driven filters — show all for now until thread_brief table exists
                break
            }

        case .account(let accountId):
            conditions.append("t.account_id = ?")
            arguments.append(accountId)
        }

        // Chip filter as additional narrowing
        switch filter {
        case .all:
            break
        case .hasAttachment:
            conditions.append("""
                EXISTS (SELECT 1 FROM message m3 JOIN attachment a2 ON a2.message_id = m3.id WHERE m3.thread_id = t.id)
                """)
        case .needsReply, .hasDeadline, .aiHandled:
            // Brief-driven — no-op for now
            break
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        let threadSQL = """
            SELECT t.* FROM thread t
            \(whereClause)
            ORDER BY t.last_message_at DESC
            """

        let threads = try ThreadRecord.fetchAll(
            db,
            sql: threadSQL,
            arguments: StatementArguments(arguments)
        )

        // Batch query: latest from_addr per thread
        let senderRows = try Row.fetchAll(
            db,
            sql: """
                SELECT m.thread_id, m.from_addr
                FROM message m
                INNER JOIN (
                    SELECT thread_id, MAX(sent_at) AS max_sent
                    FROM message
                    GROUP BY thread_id
                ) latest ON m.thread_id = latest.thread_id
                    AND m.sent_at = latest.max_sent
                """
        )
        var senderByThread: [String: String] = [:]
        for row in senderRows {
            let tid: String = row["thread_id"]
            let from: String? = row["from_addr"]
            senderByThread[tid] = from ?? ""
        }

        // Batch query: attachment count per thread
        let attRows = try Row.fetchAll(
            db,
            sql: """
                SELECT m.thread_id, COUNT(*) AS cnt
                FROM attachment a
                JOIN message m ON m.id = a.message_id
                GROUP BY m.thread_id
                """
        )
        var attByThread: [String: Int] = [:]
        for row in attRows {
            let tid: String = row["thread_id"]
            let cnt: Int = row["cnt"]
            attByThread[tid] = cnt
        }

        return threads.map { thread in
            (thread, senderByThread[thread.id], attByThread[thread.id] ?? 0)
        }
    }
}
