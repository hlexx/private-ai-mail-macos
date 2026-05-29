import GRDB
import Persistence

// MARK: - Folder counts observation (extracted to reduce InboxStore file length)

extension InboxStore {
    func startCountsObservation() {
        countsTask?.cancel()
        let currentSelection = selection
        countsTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db -> [FolderID: Int] in
                var counts = try Self.labelBasedCounts(db: db, selection: currentSelection)
                let briefCounts = try Self.briefBasedCounts(db: db, selection: currentSelection)
                counts.merge(briefCounts) { _, new in new }
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

    private nonisolated static func accountId(from selection: SidebarSelection) -> String? {
        if case .account(let id) = selection { return id }
        return nil
    }

    private nonisolated static func labelBasedCounts(
        db: Database,
        selection: SidebarSelection
    ) throws -> [FolderID: Int] {
        var counts: [FolderID: Int] = [:]
        let aid = accountId(from: selection)

        let accountFilter = aid != nil ? " WHERE tl.account_id = ? AND" : " WHERE"
        let accountArgs: [DatabaseValueConvertible] = aid.map { [$0] } ?? []

        for folder in [FolderID.inbox, .starred, .sent, .trash, .spam] {
            guard let label = folder.gmailLabel else { continue }
            counts[folder] = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM thread_label tl" + accountFilter + " tl.label_id = ?",
                arguments: StatementArguments(accountArgs + [label])
            ) ?? 0
        }

        let threadFilter = aid != nil ? " AND t.account_id = ?" : ""
        let threadArgs: [DatabaseValueConvertible] = aid.map { [$0] } ?? []
        counts[.archive] = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM thread t
                WHERE NOT EXISTS (
                    SELECT 1 FROM thread_label tl_ex
                    WHERE tl_ex.account_id = t.account_id AND tl_ex.thread_id = t.id AND tl_ex.label_id IN ('INBOX','TRASH','SPAM','SENT','DRAFT')
                )
                """ + threadFilter,
            arguments: StatementArguments(threadArgs)
        ) ?? 0

        let msgFilter = aid != nil ? " WHERE m.account_id = ?" : ""
        let msgArgs: [DatabaseValueConvertible] = aid.map { [$0] } ?? []
        counts[.attachments] = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(DISTINCT m.account_id || '/' || m.thread_id) FROM message m
                JOIN attachment a ON a.account_id = m.account_id AND a.message_id = m.id
                """ + msgFilter,
            arguments: StatementArguments(msgArgs)
        ) ?? 0

        return counts
    }

    private nonisolated static func briefBasedCounts(
        db: Database,
        selection: SidebarSelection
    ) throws -> [FolderID: Int] {
        var counts: [FolderID: Int] = [:]
        let aid = accountId(from: selection)
        let briefFilter = aid != nil ? " AND tb.account_id = ?" : ""
        let briefArgs: [DatabaseValueConvertible] = aid.map { [$0] } ?? []

        let base = """
            SELECT COUNT(*) FROM thread_brief tb
            JOIN thread_label tl ON tl.account_id = tb.account_id AND tl.thread_id = tb.thread_id AND tl.label_id = 'INBOX'
            WHERE 1=1
            """

        counts[.needsReply] = try Int.fetchOne(
            db,
            sql: base + briefFilter + " AND tb.request IS NOT NULL AND TRIM(tb.request) <> ''",
            arguments: StatementArguments(briefArgs)
        ) ?? 0

        counts[.hasDeadline] = try Int.fetchOne(
            db,
            sql: base + briefFilter + " AND tb.deadline IS NOT NULL AND TRIM(tb.deadline) <> ''",
            arguments: StatementArguments(briefArgs)
        ) ?? 0

        return counts
    }
}
