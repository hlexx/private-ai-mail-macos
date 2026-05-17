// swiftlint:disable type_body_length function_body_length
#if DEBUG

import Foundation
import GRDB
import Persistence

/// DEBUG-only seeder that populates the local DB with seven synthetic email
/// threads modelled after `design/re-box/project/app/data.js` from the
/// Claude Design handoff. The fixtures cover the full spectrum of signal
/// chips (due / reply / att / ai / logged / cc / cal / paid) and AI brief
/// states so every UI affordance can be exercised without connecting a
/// real Gmail account.
///
/// Idempotent: if any account already exists in the DB, this is a no-op.
/// Not compiled into release builds — guarded by `#if DEBUG`.
enum DevSeeder {

    /// Seed once when the DB is empty. Safe to call at every launch.
    @MainActor
    static func seedIfEmpty(db: AppDatabase) {
        Task { @DatabaseActor in
            do {
                let count = try db.dbQueue.read { try AccountRecord.fetchCount($0) }
                guard count == 0 else { return }
                try db.dbQueue.write { db in
                    try insertSeed(into: db)
                }
            } catch {
                // Best-effort dev affordance — never crash the app.
            }
        }
    }

    // MARK: - Seed payload

    private static func insertSeed(into db: Database) throws {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let nowTs = Int(now.timeIntervalSince1970)

        // Helper to build epoch-second timestamps relative to today.
        func ts(_ component: Calendar.Component, _ value: Int, hour: Int = 9, minute: Int = 0) -> Int {
            guard let date = cal.date(byAdding: component, value: -value, to: now) else { return nowTs }
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            var setComps = comps
            setComps.hour = hour
            setComps.minute = minute
            return Int((cal.date(from: setComps) ?? date).timeIntervalSince1970)
        }

        // ── Accounts ───────────────────────────────────────────────
        let workAccountID = "demo-work-gmail"
        let partnersAccountID = "demo-work-m365"
        let personalAccountID = "demo-personal-gmail"

        let accounts: [AccountRecord] = [
            AccountRecord(
                id: workAccountID,
                provider: "gmail",
                email: "alex@studio.eu",
                displayName: "Work · Gmail",
                createdAt: nowTs,
                lastSyncedAt: nowTs
            ),
            AccountRecord(
                id: partnersAccountID,
                provider: "gmail",
                email: "a.chen@partners.io",
                displayName: "Work · M365",
                createdAt: nowTs,
                lastSyncedAt: nowTs
            ),
            AccountRecord(
                id: personalAccountID,
                provider: "gmail",
                email: "alex@me.eu",
                displayName: "Personal",
                createdAt: nowTs,
                lastSyncedAt: nowTs
            ),
        ]
        for account in accounts {
            try account.insert(db)
            try SyncStateRecord(
                accountId: account.id,
                historyId: nil,
                lastBootstrapAt: nowTs,
                status: "idle"
            ).insert(db)
        }

        // ── Thread fixtures ────────────────────────────────────────
        // Each entry: (id, account, subject, snippet, fromName, fromAddr,
        //              ageDays, hour, hasUnread, messageBodies, attachment?)
        struct ThreadSeed {
            let id: String
            let accountID: String
            let subject: String
            let snippet: String
            let fromName: String
            let fromAddr: String
            let ageDays: Int
            let hour: Int
            let minute: Int
            let hasUnread: Bool
            let messages: [(from: String, fromAddr: String, hoursAgo: Int, body: String)]
            let attachment: (filename: String, size: Int)?
        }

        let threads: [ThreadSeed] = [
            ThreadSeed(
                id: "demo-t1",
                accountID: workAccountID,
                subject: "Contract approval — Acme GmbH",
                snippet: "Client approved pricing and asks for the contract draft by Friday…",
                fromName: "Marta Kowalski",
                fromAddr: "marta@acme.de",
                ageDays: 0,
                hour: 11,
                minute: 42,
                hasUnread: true,
                messages: [
                    (
                        from: "Marta Kowalski",
                        fromAddr: "marta@acme.de",
                        hoursAgo: 50,
                        body: """
                        Hi Alex — we reviewed the proposal. Pricing works.
                        Can you send the contract draft by Friday so we can sign next week?
                        """
                    ),
                    (
                        from: "Alex (you)",
                        fromAddr: "alex@studio.eu",
                        hoursAgo: 45,
                        body: "Marta, glad we're aligned. I'll have a draft over before end of week."
                    ),
                    (
                        from: "Marta Kowalski",
                        fromAddr: "marta@acme.de",
                        hoursAgo: 1,
                        body: """
                        Quick nudge — Friday EOD would be ideal, otherwise we miss the legal window.
                        Attaching the last revision of the contract for reference.
                        """
                    ),
                ],
                attachment: ("contract.pdf", 284 * 1024)
            ),
            ThreadSeed(
                id: "demo-t2",
                accountID: partnersAccountID,
                subject: "Re: SaaS renewal — Q3",
                snippet: "Adding the legal team. Can you confirm the seat count by Wednesday?",
                fromName: "Jonas Reichert",
                fromAddr: "jonas@bigbank.example",
                ageDays: 0,
                hour: 10,
                minute: 8,
                hasUnread: true,
                messages: [
                    (
                        from: "Jonas Reichert",
                        fromAddr: "jonas@bigbank.example",
                        hoursAgo: 17,
                        body: """
                        Hey — kicking off Q3 renewal. Adding our legal team.
                        Can you confirm the seat count by Wednesday?
                        """
                    ),
                ],
                attachment: nil
            ),
            ThreadSeed(
                id: "demo-t3",
                accountID: personalAccountID,
                subject: "Lease addendum",
                snippet: "Attached. Let me know if 12 months is fine.",
                fromName: "Cveta Vlahova",
                fromAddr: "cveta@landlord.example",
                ageDays: 1,
                hour: 16,
                minute: 20,
                hasUnread: false,
                messages: [
                    (
                        from: "Cveta Vlahova",
                        fromAddr: "cveta@landlord.example",
                        hoursAgo: 22,
                        body: "Attached the addendum. Let me know if 12 months is fine."
                    ),
                ],
                attachment: ("lease_addendum.pdf", 112 * 1024)
            ),
            ThreadSeed(
                id: "demo-t4",
                accountID: workAccountID,
                subject: "Re: pricing thread",
                snippet: "Logged to HubSpot · 2 action items extracted",
                fromName: "Sven Christensen",
                fromAddr: "sven@studio.eu",
                ageDays: 2,
                hour: 14,
                minute: 5,
                hasUnread: false,
                messages: [
                    (
                        from: "Sven Christensen",
                        fromAddr: "sven@studio.eu",
                        hoursAgo: 50,
                        body: """
                        Thanks for the call. I logged the highlights to HubSpot and pulled
                        out two action items. Will follow up after the demo next Tuesday.
                        """
                    ),
                ],
                attachment: nil
            ),
            ThreadSeed(
                id: "demo-t5",
                accountID: partnersAccountID,
                subject: "Design review — Tue 4pm",
                snippet: "Calendar invite + Figma link inside. Bring Q3 mocks.",
                fromName: "Lena Park",
                fromAddr: "lena@partners.io",
                ageDays: 2,
                hour: 9,
                minute: 30,
                hasUnread: false,
                messages: [
                    (
                        from: "Lena Park",
                        fromAddr: "lena@partners.io",
                        hoursAgo: 54,
                        body: """
                        Booking a design review for Tuesday at 4pm.
                        Bring the Q3 mocks; Figma link in the calendar invite.
                        """
                    ),
                ],
                attachment: nil
            ),
            ThreadSeed(
                id: "demo-t6",
                accountID: workAccountID,
                subject: "Weekly digest — 4 candidates",
                snippet: "Filtered by your rules. 2 strong, 1 maybe, 1 archived.",
                fromName: "Recruiting · Notion",
                fromAddr: "no-reply@notion.so",
                ageDays: 3,
                hour: 7,
                minute: 0,
                hasUnread: false,
                messages: [
                    (
                        from: "Recruiting · Notion",
                        fromAddr: "no-reply@notion.so",
                        hoursAgo: 78,
                        body: """
                        Weekly recruiting digest. Filtered by your rules.
                        2 strong, 1 maybe, 1 archived. Open Notion to review.
                        """
                    ),
                ],
                attachment: nil
            ),
            ThreadSeed(
                id: "demo-t7",
                accountID: personalAccountID,
                subject: "Invoice #INV-2418",
                snippet: "Paid · €1,840 · receipt attached",
                fromName: "Stripe",
                fromAddr: "receipts@stripe.com",
                ageDays: 4,
                hour: 8,
                minute: 15,
                hasUnread: false,
                messages: [
                    (
                        from: "Stripe",
                        fromAddr: "receipts@stripe.com",
                        hoursAgo: 102,
                        body: "Receipt for €1,840 attached. Thanks for your business."
                    ),
                ],
                attachment: ("receipt_INV-2418.pdf", 84 * 1024)
            ),
        ]

        // ── System labels per account ─────────────────────────────
        let systemLabelIDs = ["INBOX", "SENT", "DRAFT", "TRASH", "SPAM", "STARRED", "IMPORTANT", "UNREAD"]
        for account in accounts {
            for labelID in systemLabelIDs {
                try LabelRecord(
                    id: labelID,
                    accountId: account.id,
                    name: labelID.capitalized,
                    type: .system,
                    color: nil,
                    messagesUnreadCount: 0,
                    messagesTotalCount: 0
                ).insert(db)
            }
        }

        for seed in threads {
            let threadTs = ts(.day, seed.ageDays, hour: seed.hour, minute: seed.minute)
            try ThreadRecord(
                id: seed.id,
                accountId: seed.accountID,
                subject: seed.subject,
                snippet: seed.snippet,
                lastMessageAt: threadTs,
                messageCount: seed.messages.count,
                hasUnread: seed.hasUnread ? 1 : 0
            ).insert(db)

            // Add thread labels: all demo threads go to INBOX
            try ThreadLabelRecord(accountId: seed.accountID, threadId: seed.id, labelId: "INBOX").insert(db)
            if seed.hasUnread {
                try ThreadLabelRecord(accountId: seed.accountID, threadId: seed.id, labelId: "UNREAD").insert(db)
            }
            // Star the first thread for testing
            if seed.id == "demo-t1" {
                try ThreadLabelRecord(accountId: seed.accountID, threadId: seed.id, labelId: "STARRED").insert(db)
            }

            for (index, msg) in seed.messages.enumerated() {
                let messageID = "\(seed.id)-m\(index + 1)"
                let messageTs = max(threadTs - (msg.hoursAgo * 3600), threadTs - 3 * 86400)
                try MessageRecord(
                    id: messageID,
                    threadId: seed.id,
                    accountId: seed.accountID,
                    messageIdHeader: "<\(messageID)@demo.local>",
                    fromAddr: "\(msg.from) <\(msg.fromAddr)>",
                    toAddr: "alex@studio.eu",
                    ccAddr: nil,
                    sentAt: messageTs,
                    snippet: String(msg.body.prefix(140)),
                    bodyHtml: nil,
                    bodyText: msg.body,
                    flags: seed.hasUnread && index == seed.messages.count - 1 ? 0 : MessageRecord.read
                ).insert(db)
            }

            if let attachment = seed.attachment {
                try AttachmentRecord(
                    id: "\(seed.id)-att1",
                    messageId: "\(seed.id)-m\(seed.messages.count)",
                    accountId: seed.accountID,
                    filename: attachment.filename,
                    mime: "application/pdf",
                    sizeBytes: attachment.size
                ).insert(db)
            }
        }
    }
}
// swiftlint:enable type_body_length function_body_length

#endif
