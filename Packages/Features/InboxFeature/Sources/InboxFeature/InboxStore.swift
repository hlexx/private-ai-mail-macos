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
        let currentSelection = selection
        countsTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db -> [FolderID: Int] in
                var counts: [FolderID: Int] = [:]

                // When an account is selected, scope counts to that account's threads
                let accountFilter: String
                let accountArgs: [DatabaseValueConvertible]
                if case .account(let accountId) = currentSelection {
                    accountFilter = " WHERE tl.account_id = ? AND"
                    accountArgs = [accountId]
                } else {
                    accountFilter = " WHERE"
                    accountArgs = []
                }

                // Inbox count
                let inboxCount = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM thread_label tl" + accountFilter + " tl.label_id = 'INBOX'",
                    arguments: StatementArguments(accountArgs)
                ) ?? 0
                counts[.inbox] = inboxCount

                // Starred count
                let starredCount = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM thread_label tl" + accountFilter + " tl.label_id = 'STARRED'",
                    arguments: StatementArguments(accountArgs)
                ) ?? 0
                counts[.starred] = starredCount

                // Sent count
                let sentCount = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM thread_label tl" + accountFilter + " tl.label_id = 'SENT'",
                    arguments: StatementArguments(accountArgs)
                ) ?? 0
                counts[.sent] = sentCount

                // Archive count (threads not in INBOX/TRASH/SPAM/SENT/DRAFT)
                let archiveAccountFilter: String
                let archiveArgs: [DatabaseValueConvertible]
                if case .account(let accountId) = currentSelection {
                    archiveAccountFilter = " AND t.account_id = ?"
                    archiveArgs = [accountId]
                } else {
                    archiveAccountFilter = ""
                    archiveArgs = []
                }
                let archiveCount = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM thread t
                        WHERE NOT EXISTS (
                            SELECT 1 FROM thread_label tl_ex
                            WHERE tl_ex.account_id = t.account_id AND tl_ex.thread_id = t.id AND tl_ex.label_id IN ('INBOX','TRASH','SPAM','SENT','DRAFT')
                        )
                        """ + archiveAccountFilter,
                    arguments: StatementArguments(archiveArgs)
                ) ?? 0
                counts[.archive] = archiveCount

                // Attachments count
                let attAccountFilter: String
                let attArgs: [DatabaseValueConvertible]
                if case .account(let accountId) = currentSelection {
                    attAccountFilter = " WHERE m.account_id = ?"
                    attArgs = [accountId]
                } else {
                    attAccountFilter = ""
                    attArgs = []
                }
                let attCount = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(DISTINCT m.account_id || '/' || m.thread_id) FROM message m
                        JOIN attachment a ON a.account_id = m.account_id AND a.message_id = m.id
                        """ + attAccountFilter,
                    arguments: StatementArguments(attArgs)
                ) ?? 0
                counts[.attachments] = attCount

                // Brief-driven counts scoped to INBOX threads
                let briefAccountFilter: String
                let briefArgs: [DatabaseValueConvertible]
                if case .account(let accountId) = currentSelection {
                    briefAccountFilter = " AND tb.account_id = ?"
                    briefArgs = [accountId]
                } else {
                    briefAccountFilter = ""
                    briefArgs = []
                }

                let inboxBriefBase = """
                    SELECT COUNT(*) FROM thread_brief tb
                    JOIN thread_label tl ON tl.account_id = tb.account_id AND tl.thread_id = tb.thread_id AND tl.label_id = 'INBOX'
                    WHERE 1=1
                    """

                let needsReplyCount = try Int.fetchOne(
                    db,
                    sql: inboxBriefBase + briefAccountFilter
                        + " AND tb.request IS NOT NULL AND TRIM(tb.request) <> ''",
                    arguments: StatementArguments(briefArgs)
                ) ?? 0
                counts[.needsReply] = needsReplyCount

                let hasDeadlineCount = try Int.fetchOne(
                    db,
                    sql: inboxBriefBase + briefAccountFilter
                        + " AND tb.deadline IS NOT NULL AND TRIM(tb.deadline) <> ''",
                    arguments: StatementArguments(briefArgs)
                ) ?? 0
                counts[.hasDeadline] = hasDeadlineCount

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
                    t.id IN (SELECT thread_id FROM thread_label WHERE account_id = t.account_id AND label_id = ?)
                    """)
                arguments.append("INBOX")
            case .starred:
                conditions.append("""
                    t.id IN (SELECT thread_id FROM thread_label WHERE account_id = t.account_id AND label_id = ?)
                    """)
                arguments.append("STARRED")
            case .sent:
                conditions.append("""
                    t.id IN (SELECT thread_id FROM thread_label WHERE account_id = t.account_id AND label_id = ?)
                    """)
                arguments.append("SENT")
            case .archive:
                conditions.append("""
                    NOT EXISTS (
                        SELECT 1 FROM thread_label tl_ex
                        WHERE tl_ex.account_id = t.account_id AND tl_ex.thread_id = t.id AND tl_ex.label_id IN ('INBOX','TRASH','SPAM','SENT','DRAFT')
                    )
                    """)
            case .attachments:
                conditions.append("""
                    EXISTS (SELECT 1 FROM message m2 JOIN attachment a ON a.account_id = m2.account_id AND a.message_id = m2.id WHERE m2.account_id = t.account_id AND m2.thread_id = t.id)
                    """)
            case .needsReply:
                conditions.append("""
                    EXISTS (
                        SELECT 1 FROM thread_brief tb
                        WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                          AND tb.request IS NOT NULL AND TRIM(tb.request) <> ''
                    )
                    """)
            case .hasDeadline:
                conditions.append("""
                    EXISTS (
                        SELECT 1 FROM thread_brief tb
                        WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                          AND tb.deadline IS NOT NULL AND TRIM(tb.deadline) <> ''
                    )
                    """)
            case .logged:
                // Phase 2 — CRM integration. Keep returning empty for now.
                conditions.append("1 = 0")
            }

        case .account(let accountId):
            conditions.append("t.account_id = ?")
            arguments.append(accountId)
            conditions.append("""
                NOT EXISTS (
                    SELECT 1 FROM thread_label tl_ex
                    WHERE tl_ex.account_id = t.account_id AND tl_ex.thread_id = t.id AND tl_ex.label_id IN ('TRASH','SPAM','DRAFT')
                )
                """)

        case .allAccountsAllFolders:
            conditions.append("""
                t.id IN (SELECT thread_id FROM thread_label WHERE account_id = t.account_id AND label_id = 'INBOX')
                """)
        }

        // Chip filter as additional narrowing
        switch filter {
        case .all:
            break
        case .hasAttachment:
            conditions.append("""
                EXISTS (SELECT 1 FROM message m3 JOIN attachment a2 ON a2.account_id = m3.account_id AND a2.message_id = m3.id WHERE m3.account_id = t.account_id AND m3.thread_id = t.id)
                """)
        case .needsReply:
            conditions.append("""
                EXISTS (
                    SELECT 1 FROM thread_brief tb
                    WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                      AND tb.request IS NOT NULL AND TRIM(tb.request) <> ''
                )
                """)
        case .hasDeadline:
            conditions.append("""
                EXISTS (
                    SELECT 1 FROM thread_brief tb
                    WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                      AND tb.deadline IS NOT NULL AND TRIM(tb.deadline) <> ''
                )
                """)
        case .aiHandled:
            conditions.append("""
                EXISTS (
                    SELECT 1 FROM thread_brief tb
                    WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                )
                """)
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

        let threadIds = threads.map(\.id)
        guard !threadIds.isEmpty else {
            return threads.map { ($0, nil, 0) }
        }

        let (senderByThread, attByThread) = try fetchThreadMetadata(db: db, threads: threads)
        return threads.map { thread in
            let key = "\(thread.accountId)/\(thread.id)"
            return (thread, senderByThread[key], attByThread[key] ?? 0)
        }
    }

    private nonisolated static func fetchThreadMetadata(
        db: Database,
        threads: [ThreadRecord]
    ) throws -> (senders: [String: String], attachments: [String: Int]) {
        let threadIds = threads.map(\.id)
        let placeholders = threadIds.map { _ in "?" }.joined(separator: ",")

        let senderRows = try Row.fetchAll(
            db,
            sql: """
                SELECT m.account_id, m.thread_id, m.from_addr
                FROM message m
                INNER JOIN (
                    SELECT account_id, thread_id, MAX(sent_at) AS max_sent
                    FROM message
                    WHERE thread_id IN (\(placeholders))
                    GROUP BY account_id, thread_id
                ) latest ON m.account_id = latest.account_id
                    AND m.thread_id = latest.thread_id
                    AND m.sent_at = latest.max_sent
                """,
            arguments: StatementArguments(threadIds)
        )
        var senderByThread: [String: String] = [:]
        for row in senderRows {
            let aid: String = row["account_id"]
            let tid: String = row["thread_id"]
            let from: String? = row["from_addr"]
            senderByThread["\(aid)/\(tid)"] = from ?? ""
        }

        let attRows = try Row.fetchAll(
            db,
            sql: """
                SELECT m.account_id, m.thread_id, COUNT(*) AS cnt
                FROM attachment a
                JOIN message m ON m.account_id = a.account_id AND m.id = a.message_id
                WHERE m.thread_id IN (\(placeholders))
                GROUP BY m.account_id, m.thread_id
                """,
            arguments: StatementArguments(threadIds)
        )
        var attByThread: [String: Int] = [:]
        for row in attRows {
            let aid: String = row["account_id"]
            let tid: String = row["thread_id"]
            let cnt: Int = row["cnt"]
            attByThread["\(aid)/\(tid)"] = cnt
        }

        return (senderByThread, attByThread)
    }
}
