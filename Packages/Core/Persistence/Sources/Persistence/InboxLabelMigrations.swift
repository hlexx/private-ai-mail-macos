import Foundation
import GRDB

/// Backfill `INBOX` label for threads that were synced before label-aware
/// code landed (v0.1.4 and earlier). Symptom: after upgrading to 0.1.6
/// the sidebar's `All Accounts` / `Inbox` / `Sent` / `Starred` filters
/// all return empty because their SQL requires a matching row in
/// `thread_label`, and old threads never got those rows populated.
/// Treat any thread with **zero** thread_label rows as if it had been
/// observed with the `INBOX` label — that matches where the user
/// previously saw it.
///
/// Idempotent: re-runs find no zero-label threads and do nothing.
/// Future syncs overwrite this backfill the moment Gmail's labelIds
/// arrive for that thread.
enum M008_BackfillInboxLabel {
    static func migrate(_ db: Database) throws {
        // Ensure the canonical INBOX label row exists per account before
        // referencing it from thread_label (FK constraint).
        try db.execute(sql: """
            INSERT OR IGNORE INTO label (id, account_id, name, type, color, messages_unread_count, messages_total_count)
            SELECT 'INBOX', a.id, 'Inbox', 'system', NULL, 0, 0
            FROM account a
            """)

        // Insert (account_id, thread_id, 'INBOX') for every thread that
        // currently has no thread_label rows at all.
        try db.execute(sql: """
            INSERT OR IGNORE INTO thread_label (account_id, thread_id, label_id)
            SELECT t.account_id, t.id, 'INBOX'
            FROM thread t
            WHERE NOT EXISTS (
                SELECT 1 FROM thread_label tl
                WHERE tl.account_id = t.account_id AND tl.thread_id = t.id
            )
            """)
    }
}

/// Broader INBOX backfill: M008 only caught threads with **zero** label rows.
/// Many legacy threads have UNREAD / CATEGORY_PROMOTIONS / IMPORTANT but never
/// got an INBOX row. M009 inserts INBOX for any thread that:
/// - does NOT already have INBOX
/// - does NOT have TRASH, SPAM, or DRAFT (explicitly out-of-inbox)
/// - is NOT sent-only (has SENT but no other non-meta labels)
/// Idempotent: INSERT OR IGNORE prevents duplicates on re-run.
enum M009_BackfillInboxLabelV2 {
    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO label (id, account_id, name, type, color, messages_unread_count, messages_total_count)
            SELECT 'INBOX', a.id, 'Inbox', 'system', NULL, 0, 0
            FROM account a
            """)

        try db.execute(sql: """
            INSERT OR IGNORE INTO thread_label (account_id, thread_id, label_id)
            SELECT t.account_id, t.id, 'INBOX'
            FROM thread t
            WHERE NOT EXISTS (
                SELECT 1 FROM thread_label tl_in
                WHERE tl_in.account_id = t.account_id
                  AND tl_in.thread_id = t.id
                  AND tl_in.label_id = 'INBOX'
            )
            AND NOT EXISTS (
                SELECT 1 FROM thread_label tl_out
                WHERE tl_out.account_id = t.account_id
                  AND tl_out.thread_id = t.id
                  AND tl_out.label_id IN ('TRASH','SPAM','DRAFT')
            )
            AND NOT (
                EXISTS (SELECT 1 FROM thread_label tl_sent
                        WHERE tl_sent.account_id = t.account_id
                          AND tl_sent.thread_id = t.id
                          AND tl_sent.label_id = 'SENT')
                AND NOT EXISTS (SELECT 1 FROM thread_label tl_any
                                WHERE tl_any.account_id = t.account_id
                                  AND tl_any.thread_id = t.id
                                  AND tl_any.label_id NOT IN ('SENT','UNREAD','IMPORTANT'))
            )
            """)
    }
}

/// Signal to the app that a one-shot label reconciliation pass is
/// needed on next launch. Does NOT modify schema or data — just flips
/// the `pam.needsLabelReconcile` flag in UserDefaults so the running
/// app picks it up post-launch and calls `LabelReconciler.reconcileInbox`
/// per account.
///
/// The reason this migration is necessary: M008 + M009 (v0.1.7/v0.1.8)
/// were too eager — they inferred `INBOX` for any thread that didn't
/// explicitly carry `TRASH/SPAM/DRAFT`. Archived threads in Gmail look
/// the same as "should-be-inbox" from that local view, so the backfill
/// flooded Inbox with archived mail. This migration kicks off the
/// authoritative re-check against `users.messages.list?q=label:INBOX`.
enum M010_SignalLabelReconcile {
    static func migrate(_ db: Database) throws {
        UserDefaults.standard.set(true, forKey: "pam.needsLabelReconcile")
    }
}
