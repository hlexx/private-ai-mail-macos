import GRDB
import MailProviders
import Persistence

public actor MailMutator {
    private let db: AppDatabase
    private let apiFactory: GmailAPIFactory

    public init(db: AppDatabase, apiFactory: @escaping GmailAPIFactory) {
        self.db = db
        self.apiFactory = apiFactory
    }

    public func archive(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            threadId: threadId,
            accountId: accountId,
            addLabelIds: [],
            removeLabelIds: ["INBOX"]
        )
    }

    public func unarchive(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["INBOX"],
            removeLabelIds: []
        )
    }

    public func star(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["STARRED"],
            removeLabelIds: []
        )
    }

    public func unstar(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            threadId: threadId,
            accountId: accountId,
            addLabelIds: [],
            removeLabelIds: ["STARRED"]
        )
    }

    public func markRead(_ threadId: String, accountId: String, read: Bool) async throws {
        let api = try apiFactory(accountId)
        let readFlag = MessageRecord.read
        // Capture original has_unread before optimistic update for correct rollback
        let originalHasUnread: Int = (try? await db.dbQueue.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT has_unread FROM thread WHERE account_id = ? AND id = ?",
                arguments: [accountId, threadId]
            )
        }) ?? (read ? 1 : 0)

        // Optimistic local update: labels + flags in one transaction
        try await db.dbQueue.write { dbConn in
            if read {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD").delete(dbConn)
            } else {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD")
                    .insert(dbConn, onConflict: .ignore)
            }
            if read {
                try dbConn.execute(
                    sql: "UPDATE message SET flags = flags | ? WHERE account_id = ? AND thread_id = ?",
                    arguments: [readFlag, accountId, threadId]
                )
            } else {
                try dbConn.execute(
                    sql: "UPDATE message SET flags = flags & ~? WHERE account_id = ? AND thread_id = ?",
                    arguments: [readFlag, accountId, threadId]
                )
            }
            try dbConn.execute(
                sql: "UPDATE thread SET has_unread = ? WHERE account_id = ? AND id = ?",
                arguments: [read ? 0 : 1, accountId, threadId]
            )
        }

        // API call
        do {
            _ = try await api.modifyThread(
                id: threadId,
                addLabelIds: read ? [] : ["UNREAD"],
                removeLabelIds: read ? ["UNREAD"] : []
            )
        } catch {
            // Rollback all local changes on failure, restoring original has_unread
            try? await db.dbQueue.write { dbConn in
                if read {
                    try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD")
                        .insert(dbConn, onConflict: .ignore)
                } else {
                    try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD").delete(dbConn)
                }
                if read {
                    try dbConn.execute(
                        sql: "UPDATE message SET flags = flags & ~? WHERE account_id = ? AND thread_id = ?",
                        arguments: [readFlag, accountId, threadId]
                    )
                } else {
                    try dbConn.execute(
                        sql: "UPDATE message SET flags = flags | ? WHERE account_id = ? AND thread_id = ?",
                        arguments: [readFlag, accountId, threadId]
                    )
                }
                try dbConn.execute(
                    sql: "UPDATE thread SET has_unread = ? WHERE account_id = ? AND id = ?",
                    arguments: [originalHasUnread, accountId, threadId]
                )
            }
            throw error
        }
    }

    public func trash(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["TRASH"],
            removeLabelIds: ["INBOX"]
        )
    }

    public func untrash(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["INBOX"],
            removeLabelIds: ["TRASH"]
        )
    }

    // MARK: - Core mutation

    private func mutateLabels(
        threadId: String,
        accountId: String,
        addLabelIds: [String],
        removeLabelIds: [String]
    ) async throws {
        let api = try apiFactory(accountId)

        // 1. Optimistic local update
        try await db.dbQueue.write { dbConn in
            for labelId in removeLabelIds {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId).delete(dbConn)
            }
            for labelId in addLabelIds {
                let record = ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId)
                try record.insert(dbConn, onConflict: .ignore)
            }
        }

        // 2. API call
        do {
            _ = try await api.modifyThread(
                id: threadId,
                addLabelIds: addLabelIds,
                removeLabelIds: removeLabelIds
            )
        } catch {
            // 3. Rollback on failure
            try? await db.dbQueue.write { dbConn in
                for labelId in addLabelIds {
                    try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId).delete(dbConn)
                }
                for labelId in removeLabelIds {
                    let record = ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId)
                    try record.insert(dbConn, onConflict: .ignore)
                }
            }
            throw error
        }
    }
}
