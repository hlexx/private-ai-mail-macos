import Foundation
import GRDB

public struct MailSearchDocumentRecord: Codable, Sendable, FetchableRecord, TableRecord {
    public static let databaseTableName = "mail_search_document"

    public var id: Int64
    public var accountId: String
    public var messageId: String
    public var threadId: String
    public var provider: String
    public var subject: String?
    public var fromAddr: String?
    public var toAddr: String?
    public var ccAddr: String?
    public var snippet: String?
    public var bodyText: String?
    public var normalizedBodyText: String?
    public var attachmentFilenames: String?
    public var attachmentMimes: String?
    public var canonicalMailboxes: String?
    public var sentAt: Int
    public var isUnread: Int
    public var isSent: Int
    public var hasAttachment: Int
    public var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case messageId = "message_id"
        case threadId = "thread_id"
        case provider
        case subject
        case fromAddr = "from_addr"
        case toAddr = "to_addr"
        case ccAddr = "cc_addr"
        case snippet
        case bodyText = "body_text"
        case normalizedBodyText = "normalized_body_text"
        case attachmentFilenames = "attachment_filenames"
        case attachmentMimes = "attachment_mimes"
        case canonicalMailboxes = "canonical_mailboxes"
        case sentAt = "sent_at"
        case isUnread = "is_unread"
        case isSent = "is_sent"
        case hasAttachment = "has_attachment"
        case updatedAt = "updated_at"
    }
}

public struct MailSearchRebuildStateRecord: Codable, Sendable, FetchableRecord, TableRecord {
    public static let databaseTableName = "mail_search_rebuild_state"

    public var key: String
    public var schemaVersion: Int
    public var tokenizer: String
    public var needsRebuild: Int
    public var lastRebuiltAt: Int?
    public var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case key
        case schemaVersion = "schema_version"
        case tokenizer
        case needsRebuild = "needs_rebuild"
        case lastRebuiltAt = "last_rebuilt_at"
        case updatedAt = "updated_at"
    }
}

public enum LocalSearchIndexPersistence {
    public static let metadataKey = "mail_search_index"
    public static let schemaVersion = 1
    public static let tokenizer = "unicode61 remove_diacritics 2"

    public static func rebuildAll(in db: Database, now: Int = Int(Date().timeIntervalSince1970)) throws {
        try db.execute(sql: "DELETE FROM mail_search_document")
        let rows = try MailSearchSourceRow.fetchAll(db, sql: Self.sourceRowsSQL)
        for row in rows {
            try upsert(row, in: db, now: now)
        }
        try markRebuilt(in: db, at: now)
    }

    public static func upsertMessage(
        accountId: String,
        messageId: String,
        in db: Database,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        if let row = try MailSearchSourceRow.fetchOne(
            db,
            sql: Self.sourceRowsSQL + " WHERE m.account_id = ? AND m.id = ?",
            arguments: [accountId, messageId]
        ) {
            try upsert(row, in: db, now: now)
        } else {
            try deleteMessage(accountId: accountId, messageId: messageId, in: db)
        }
    }

    public static func deleteMessage(accountId: String, messageId: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM mail_search_document WHERE account_id = ? AND message_id = ?",
            arguments: [accountId, messageId]
        )
    }

    public static func markRebuildNeeded(in db: Database, now: Int = Int(Date().timeIntervalSince1970)) throws {
        try db.execute(
            sql: """
                UPDATE mail_search_rebuild_state
                SET needs_rebuild = 1,
                    updated_at = ?
                WHERE key = ?
                """,
            arguments: [now, metadataKey]
        )
    }

    private static let sourceRowsSQL = """
        SELECT
            m.account_id,
            m.id AS message_id,
            m.thread_id,
            a.provider,
            t.subject,
            m.from_addr,
            m.to_addr,
            m.cc_addr,
            COALESCE(m.snippet, t.snippet) AS snippet,
            m.body_text,
            m.body_html,
            m.flags,
            m.sent_at,
            COALESCE((
                SELECT group_concat(filename, ' ')
                FROM attachment
                WHERE account_id = m.account_id
                  AND message_id = m.id
                  AND filename IS NOT NULL
                  AND filename <> ''
            ), '') AS attachment_filenames,
            COALESCE((
                SELECT group_concat(mime, ' ')
                FROM attachment
                WHERE account_id = m.account_id
                  AND message_id = m.id
                  AND mime IS NOT NULL
                  AND mime <> ''
            ), '') AS attachment_mimes,
            COALESCE((
                SELECT group_concat(label_id, ' ')
                FROM thread_label
                WHERE account_id = m.account_id
                  AND thread_id = m.thread_id
            ), '') AS canonical_mailboxes,
            EXISTS (
                SELECT 1
                FROM attachment
                WHERE account_id = m.account_id
                  AND message_id = m.id
            ) AS has_attachment
        FROM message m
        JOIN account a ON a.id = m.account_id
        JOIN thread t ON t.account_id = m.account_id AND t.id = m.thread_id
        """

    private static func upsert(_ row: MailSearchSourceRow, in db: Database, now: Int) throws {
        let normalizedBodyText = row.bodyHtml.flatMap(MessageRecord.htmlToPlainText)
        try db.execute(
            sql: """
                INSERT INTO mail_search_document (
                    account_id,
                    message_id,
                    thread_id,
                    provider,
                    subject,
                    from_addr,
                    to_addr,
                    cc_addr,
                    snippet,
                    body_text,
                    normalized_body_text,
                    attachment_filenames,
                    attachment_mimes,
                    canonical_mailboxes,
                    sent_at,
                    is_unread,
                    is_sent,
                    has_attachment,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, message_id) DO UPDATE SET
                    thread_id = excluded.thread_id,
                    provider = excluded.provider,
                    subject = excluded.subject,
                    from_addr = excluded.from_addr,
                    to_addr = excluded.to_addr,
                    cc_addr = excluded.cc_addr,
                    snippet = excluded.snippet,
                    body_text = excluded.body_text,
                    normalized_body_text = excluded.normalized_body_text,
                    attachment_filenames = excluded.attachment_filenames,
                    attachment_mimes = excluded.attachment_mimes,
                    canonical_mailboxes = excluded.canonical_mailboxes,
                    sent_at = excluded.sent_at,
                    is_unread = excluded.is_unread,
                    is_sent = excluded.is_sent,
                    has_attachment = excluded.has_attachment,
                    updated_at = excluded.updated_at
                """,
            arguments: [
                row.accountId,
                row.messageId,
                row.threadId,
                row.provider,
                row.subject,
                row.fromAddr,
                row.toAddr,
                row.ccAddr,
                row.snippet,
                row.bodyText,
                normalizedBodyText,
                row.attachmentFilenames.nilIfEmpty,
                row.attachmentMimes.nilIfEmpty,
                row.canonicalMailboxes.nilIfEmpty,
                row.sentAt,
                row.isUnread,
                row.isSent,
                row.hasAttachment,
                now,
            ]
        )
    }

    private static func markRebuilt(in db: Database, at timestamp: Int) throws {
        try db.execute(
            sql: """
                UPDATE mail_search_rebuild_state
                SET needs_rebuild = 0,
                    last_rebuilt_at = ?,
                    updated_at = ?
                WHERE key = ?
                """,
            arguments: [timestamp, timestamp, metadataKey]
        )
    }
}

private struct MailSearchSourceRow: FetchableRecord {
    var accountId: String
    var messageId: String
    var threadId: String
    var provider: String
    var subject: String?
    var fromAddr: String?
    var toAddr: String?
    var ccAddr: String?
    var snippet: String?
    var bodyText: String?
    var bodyHtml: String?
    var flags: Int
    var sentAt: Int
    var attachmentFilenames: String
    var attachmentMimes: String
    var canonicalMailboxes: String
    var hasAttachment: Int

    init(row: Row) {
        accountId = row["account_id"]
        messageId = row["message_id"]
        threadId = row["thread_id"]
        provider = row["provider"]
        subject = row["subject"]
        fromAddr = row["from_addr"]
        toAddr = row["to_addr"]
        ccAddr = row["cc_addr"]
        snippet = row["snippet"]
        bodyText = row["body_text"]
        bodyHtml = row["body_html"]
        flags = row["flags"]
        sentAt = row["sent_at"]
        attachmentFilenames = row["attachment_filenames"]
        attachmentMimes = row["attachment_mimes"]
        canonicalMailboxes = row["canonical_mailboxes"]
        hasAttachment = row["has_attachment"]
    }

    var isUnread: Int {
        (flags & MessageRecord.read) == 0 ? 1 : 0
    }

    var isSent: Int {
        (flags & MessageRecord.sentByMe) == 0 ? 0 : 1
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum M016_LocalSearchIndex {
    static func migrate(_ db: Database) throws {
        try db.create(table: "mail_search_rebuild_state") { t in
            t.primaryKey("key", .text)
            t.column("schema_version", .integer).notNull()
            t.column("tokenizer", .text).notNull()
            t.column("needs_rebuild", .integer).notNull().defaults(to: 1)
            t.column("last_rebuilt_at", .integer)
            t.column("updated_at", .integer).notNull()
        }

        try db.create(table: "mail_search_document") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("account_id", .text)
                .notNull()
                .references("account", onDelete: .cascade)
            t.column("message_id", .text).notNull()
            t.column("thread_id", .text).notNull()
            t.column("provider", .text).notNull()
            t.column("subject", .text)
            t.column("from_addr", .text)
            t.column("to_addr", .text)
            t.column("cc_addr", .text)
            t.column("snippet", .text)
            t.column("body_text", .text)
            t.column("normalized_body_text", .text)
            t.column("attachment_filenames", .text)
            t.column("attachment_mimes", .text)
            t.column("canonical_mailboxes", .text)
            t.column("sent_at", .integer).notNull()
            t.column("is_unread", .integer).notNull().defaults(to: 0)
            t.column("is_sent", .integer).notNull().defaults(to: 0)
            t.column("has_attachment", .integer).notNull().defaults(to: 0)
            t.column("updated_at", .integer).notNull()
            t.uniqueKey(["account_id", "message_id"])
            t.foreignKey(
                ["account_id", "message_id"],
                references: "message",
                columns: ["account_id", "id"],
                onDelete: .cascade
            )
            t.foreignKey(
                ["account_id", "thread_id"],
                references: "thread",
                columns: ["account_id", "id"],
                onDelete: .cascade
            )
        }

        try db.create(
            index: "idx_mail_search_document_account",
            on: "mail_search_document",
            columns: ["account_id", "sent_at"]
        )
        try db.create(
            index: "idx_mail_search_document_thread",
            on: "mail_search_document",
            columns: ["account_id", "thread_id"]
        )
        try db.create(
            index: "idx_mail_search_document_filters",
            on: "mail_search_document",
            columns: ["account_id", "provider", "is_unread", "is_sent", "has_attachment"]
        )

        try db.execute(sql: """
            CREATE VIRTUAL TABLE mail_search_fts USING fts5(
                subject,
                from_addr,
                to_addr,
                cc_addr,
                snippet,
                body_text,
                normalized_body_text,
                attachment_filenames,
                canonical_mailboxes,
                content='mail_search_document',
                content_rowid='id',
                tokenize='unicode61 remove_diacritics 2'
            )
            """)

        try db.execute(sql: """
            CREATE TRIGGER mail_search_document_ai AFTER INSERT ON mail_search_document BEGIN
                INSERT INTO mail_search_fts(
                    rowid,
                    subject,
                    from_addr,
                    to_addr,
                    cc_addr,
                    snippet,
                    body_text,
                    normalized_body_text,
                    attachment_filenames,
                    canonical_mailboxes
                )
                VALUES (
                    new.id,
                    new.subject,
                    new.from_addr,
                    new.to_addr,
                    new.cc_addr,
                    new.snippet,
                    new.body_text,
                    new.normalized_body_text,
                    new.attachment_filenames,
                    new.canonical_mailboxes
                );
            END
            """)

        try db.execute(sql: """
            CREATE TRIGGER mail_search_document_ad AFTER DELETE ON mail_search_document BEGIN
                INSERT INTO mail_search_fts(
                    mail_search_fts,
                    rowid,
                    subject,
                    from_addr,
                    to_addr,
                    cc_addr,
                    snippet,
                    body_text,
                    normalized_body_text,
                    attachment_filenames,
                    canonical_mailboxes
                )
                VALUES (
                    'delete',
                    old.id,
                    old.subject,
                    old.from_addr,
                    old.to_addr,
                    old.cc_addr,
                    old.snippet,
                    old.body_text,
                    old.normalized_body_text,
                    old.attachment_filenames,
                    old.canonical_mailboxes
                );
            END
            """)

        try db.execute(sql: """
            CREATE TRIGGER mail_search_document_au AFTER UPDATE ON mail_search_document BEGIN
                INSERT INTO mail_search_fts(
                    mail_search_fts,
                    rowid,
                    subject,
                    from_addr,
                    to_addr,
                    cc_addr,
                    snippet,
                    body_text,
                    normalized_body_text,
                    attachment_filenames,
                    canonical_mailboxes
                )
                VALUES (
                    'delete',
                    old.id,
                    old.subject,
                    old.from_addr,
                    old.to_addr,
                    old.cc_addr,
                    old.snippet,
                    old.body_text,
                    old.normalized_body_text,
                    old.attachment_filenames,
                    old.canonical_mailboxes
                );
                INSERT INTO mail_search_fts(
                    rowid,
                    subject,
                    from_addr,
                    to_addr,
                    cc_addr,
                    snippet,
                    body_text,
                    normalized_body_text,
                    attachment_filenames,
                    canonical_mailboxes
                )
                VALUES (
                    new.id,
                    new.subject,
                    new.from_addr,
                    new.to_addr,
                    new.cc_addr,
                    new.snippet,
                    new.body_text,
                    new.normalized_body_text,
                    new.attachment_filenames,
                    new.canonical_mailboxes
                );
            END
            """)

        try db.execute(
            sql: """
                INSERT INTO mail_search_rebuild_state (
                    key,
                    schema_version,
                    tokenizer,
                    needs_rebuild,
                    last_rebuilt_at,
                    updated_at
                )
                VALUES (?, ?, ?, 1, NULL, CAST(strftime('%s', 'now') AS INTEGER))
                """,
            arguments: [
                LocalSearchIndexPersistence.metadataKey,
                LocalSearchIndexPersistence.schemaVersion,
                LocalSearchIndexPersistence.tokenizer,
            ]
        )
    }
}
