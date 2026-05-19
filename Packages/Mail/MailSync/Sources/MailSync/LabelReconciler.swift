import GRDB
import MailProviders
import Persistence

/// One-shot fixer for the broken state introduced by M008/M009 backfill
/// migrations (v0.1.7/v0.1.8): they wrote `INBOX` rows into
/// `thread_label` for threads that were genuinely archived in Gmail
/// (no `INBOX/TRASH/SPAM/DRAFT` locally + missing label data on legacy
/// threads from pre-step-10 syncs). Result: Inbox showed every thread,
/// Archive was empty.
///
/// `LabelReconciler.reconcileInbox(accountId:)` is the cure: ask Gmail
/// for every message currently labeled `INBOX`, dedupe to a set of
/// thread IDs, and replace this account's `thread_label.INBOX` rows
/// with that authoritative set. Other labels (`STARRED`, `SENT`,
/// user-defined) are untouched. Existing `thread_brief` rows survive.
///
/// Triggered automatically on first launch of v0.1.10-alpha via a flag
/// set by migration M010. Subsequent launches do nothing; the user can
/// re-run via Settings → Accounts → "Refresh labels" if needed.
public actor LabelReconciler {
    private let db: AppDatabase
    private let apiFactory: @Sendable (String) -> any GmailAPI

    public init(db: AppDatabase, apiFactory: @Sendable @escaping (String) -> any GmailAPI) {
        self.db = db
        self.apiFactory = apiFactory
    }

    /// Page through `users.messages.list?q=label:INBOX` for the account,
    /// collect the unique `threadId` set, then rewrite the account's
    /// `thread_label` rows where `label_id = 'INBOX'` to match exactly.
    public func reconcileInbox(accountId: String) async throws {
        let api = apiFactory(accountId)

        var pageToken: String? = nil
        var collected: Set<String> = []

        repeat {
            let response = try await api.listMessages(
                query: "label:INBOX",
                pageToken: pageToken,
                maxResults: 500
            )
            for msg in response.messages ?? [] {
                collected.insert(msg.threadId)
            }
            pageToken = response.nextPageToken
        } while pageToken != nil

        // Capture as `let` (Sendable Set<String>) so the db.write closure
        // can reference it without the "captured var in concurrently-
        // executing code" Swift 6 strict-concurrency error.
        let inboxThreadIds = collected

        // Ensure the canonical INBOX label row exists for this account
        // before referencing it from thread_label (FK constraint).
        try await db.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO label
                    (id, account_id, name, type, color, messages_unread_count, messages_total_count)
                VALUES (?, ?, ?, ?, NULL, 0, 0)
                """,
                arguments: ["INBOX", accountId, "Inbox", "system"]
            )

            // Wipe current INBOX rows for this account, then re-insert
            // from Gmail's authoritative list. Other labels untouched.
            try db.execute(
                sql: "DELETE FROM thread_label WHERE account_id = ? AND label_id = ?",
                arguments: [accountId, "INBOX"]
            )

            for threadId in inboxThreadIds {
                // Only insert if the thread exists locally — Gmail may
                // return inbox threads we haven't synced yet (e.g. very
                // recent ones bootstrapping in parallel). Those will
                // get INBOX naturally on next sync.
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO thread_label (account_id, thread_id, label_id)
                    SELECT ?, ?, ?
                    WHERE EXISTS (SELECT 1 FROM thread WHERE account_id = ? AND id = ?)
                    """,
                    arguments: [accountId, threadId, "INBOX", accountId, threadId]
                )
            }
        }
    }
}
