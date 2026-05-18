import GRDB
import Persistence

// MARK: - Query building (extracted to reduce InboxStore file length)

extension InboxStore {
    struct FilterCondition {
        var sql: [String] = []
        var arguments: [DatabaseValueConvertible] = []
    }

    nonisolated static func queryThreads(
        db: Database,
        selection: SidebarSelection,
        filter: ThreadFilter
    ) throws -> [(ThreadRecord, String?, Int)] {
        var cond = selectionCondition(selection)
        let filterCond = chipFilterCondition(filter)
        cond.sql.append(contentsOf: filterCond.sql)
        cond.arguments.append(contentsOf: filterCond.arguments)

        let whereClause = cond.sql.isEmpty ? "" : "WHERE " + cond.sql.joined(separator: " AND ")

        let threadSQL = """
            SELECT t.* FROM thread t
            \(whereClause)
            ORDER BY t.last_message_at DESC
            """

        let threads = try ThreadRecord.fetchAll(
            db,
            sql: threadSQL,
            arguments: StatementArguments(cond.arguments)
        )

        guard !threads.isEmpty else {
            return threads.map { ($0, nil, 0) }
        }

        let (senderByThread, attByThread) = try fetchThreadMetadata(db: db, threads: threads)
        return threads.map { thread in
            let key = "\(thread.accountId)/\(thread.id)"
            return (thread, senderByThread[key], attByThread[key] ?? 0)
        }
    }

    // MARK: - Selection conditions

    private nonisolated static func selectionCondition(_ selection: SidebarSelection) -> FilterCondition {
        var cond = FilterCondition()
        switch selection {
        case .folder(let folderID):
            appendFolderCondition(folderID, to: &cond)
        case .account(let accountId):
            cond.sql.append("t.account_id = ?")
            cond.arguments.append(accountId)
            cond.sql.append("""
                NOT EXISTS (
                    SELECT 1 FROM thread_label tl_ex
                    WHERE tl_ex.account_id = t.account_id AND tl_ex.thread_id = t.id AND tl_ex.label_id IN ('TRASH','SPAM','DRAFT')
                )
                """)
        case .allAccountsAllFolders:
            cond.sql.append("""
                t.id IN (SELECT thread_id FROM thread_label WHERE account_id = t.account_id AND label_id = 'INBOX')
                """)
        }
        return cond
    }

    private nonisolated static func appendFolderCondition(_ folderID: FolderID, to cond: inout FilterCondition) {
        switch folderID {
        case .inbox:
            cond.sql.append("""
                t.id IN (SELECT thread_id FROM thread_label WHERE account_id = t.account_id AND label_id = ?)
                """)
            cond.arguments.append("INBOX")
        case .starred:
            cond.sql.append("""
                t.id IN (SELECT thread_id FROM thread_label WHERE account_id = t.account_id AND label_id = ?)
                """)
            cond.arguments.append("STARRED")
        case .sent:
            cond.sql.append("""
                t.id IN (SELECT thread_id FROM thread_label WHERE account_id = t.account_id AND label_id = ?)
                """)
            cond.arguments.append("SENT")
        case .archive:
            cond.sql.append("""
                NOT EXISTS (
                    SELECT 1 FROM thread_label tl_ex
                    WHERE tl_ex.account_id = t.account_id AND tl_ex.thread_id = t.id AND tl_ex.label_id IN ('INBOX','TRASH','SPAM','SENT','DRAFT')
                )
                """)
        case .attachments:
            cond.sql.append("""
                EXISTS (SELECT 1 FROM message m2 JOIN attachment a ON a.account_id = m2.account_id AND a.message_id = m2.id WHERE m2.account_id = t.account_id AND m2.thread_id = t.id)
                """)
        case .needsReply:
            cond.sql.append("""
                EXISTS (
                    SELECT 1 FROM thread_brief tb
                    WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                      AND tb.request IS NOT NULL AND TRIM(tb.request) <> ''
                )
                """)
            cond.sql.append("""
                EXISTS (
                    SELECT 1 FROM thread_label tl_inbox
                    WHERE tl_inbox.account_id = t.account_id AND tl_inbox.thread_id = t.id AND tl_inbox.label_id = 'INBOX'
                )
                """)
        case .hasDeadline:
            cond.sql.append("""
                EXISTS (
                    SELECT 1 FROM thread_brief tb
                    WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                      AND tb.deadline IS NOT NULL AND TRIM(tb.deadline) <> ''
                )
                """)
            cond.sql.append("""
                EXISTS (
                    SELECT 1 FROM thread_label tl_inbox
                    WHERE tl_inbox.account_id = t.account_id AND tl_inbox.thread_id = t.id AND tl_inbox.label_id = 'INBOX'
                )
                """)
        case .logged:
            cond.sql.append("1 = 0")
        }
    }

    private nonisolated static func chipFilterCondition(_ filter: ThreadFilter) -> FilterCondition {
        var cond = FilterCondition()
        switch filter {
        case .all:
            break
        case .hasAttachment:
            cond.sql.append("""
                EXISTS (SELECT 1 FROM message m3 JOIN attachment a2 ON a2.account_id = m3.account_id AND a2.message_id = m3.id WHERE m3.account_id = t.account_id AND m3.thread_id = t.id)
                """)
        case .needsReply:
            cond.sql.append("""
                EXISTS (
                    SELECT 1 FROM thread_brief tb
                    WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                      AND tb.request IS NOT NULL AND TRIM(tb.request) <> ''
                )
                """)
        case .hasDeadline:
            cond.sql.append("""
                EXISTS (
                    SELECT 1 FROM thread_brief tb
                    WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                      AND tb.deadline IS NOT NULL AND TRIM(tb.deadline) <> ''
                )
                """)
        case .aiHandled:
            cond.sql.append("""
                EXISTS (
                    SELECT 1 FROM thread_brief tb
                    WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                )
                """)
        }
        return cond
    }

    // MARK: - Thread metadata

    nonisolated static func fetchThreadMetadata(
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
