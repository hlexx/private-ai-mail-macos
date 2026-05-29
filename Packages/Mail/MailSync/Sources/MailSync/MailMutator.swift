import GRDB
import MailProviders
import OSLog
import Persistence

public actor MailMutator {
    private static let logger = Logger(subsystem: "com.hlexx.privateaimail", category: "MailMutation")

    private let db: AppDatabase
    private let apiFactory: GmailAPIFactory

    public init(db: AppDatabase, apiFactory: @escaping GmailAPIFactory) {
        self.db = db
        self.apiFactory = apiFactory
    }

    public func archive(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            operation: .archive,
            threadId: threadId,
            accountId: accountId,
            addLabelIds: [],
            removeLabelIds: ["INBOX"]
        )
    }

    public func unarchive(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            operation: .unarchive,
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["INBOX"],
            removeLabelIds: []
        )
    }

    public func star(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            operation: .star,
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["STARRED"],
            removeLabelIds: []
        )
    }

    public func unstar(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            operation: .unstar,
            threadId: threadId,
            accountId: accountId,
            addLabelIds: [],
            removeLabelIds: ["STARRED"]
        )
    }

    public func markRead(_ threadId: String, accountId: String, read: Bool) async throws {
        let operation: MailMutationOperation = read ? .markRead : .markUnread
        let api = try resolveAPI(operation: operation, accountId: accountId, threadId: threadId)
        let readFlag = MessageRecord.read
        let snapshot = try await readSnapshot(accountId: accountId, threadId: threadId)
        logStart(operation: operation, accountId: accountId, threadId: threadId)

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

        do {
            _ = try await api.modifyThread(
                id: threadId,
                addLabelIds: read ? [] : ["UNREAD"],
                removeLabelIds: read ? ["UNREAD"] : []
            )
            logSuccess(operation: operation, accountId: accountId, threadId: threadId)
        } catch {
            let mutationError = MailMutationError.wrap(operation: operation, error: error)
            try? await db.dbQueue.write { dbConn in
                try restoreReadSnapshot(snapshot, accountId: accountId, threadId: threadId, db: dbConn)
            }
            logFailure(
                operation: operation,
                accountId: accountId,
                threadId: threadId,
                category: mutationError.category
            )
            throw mutationError
        }
    }

    public func trash(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            operation: .trash,
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["TRASH"],
            removeLabelIds: ["INBOX"]
        )
    }

    public func untrash(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            operation: .untrash,
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["INBOX"],
            removeLabelIds: ["TRASH"]
        )
    }

    // MARK: - Core mutation

    private func mutateLabels(
        operation: MailMutationOperation,
        threadId: String,
        accountId: String,
        addLabelIds: [String],
        removeLabelIds: [String]
    ) async throws {
        let api = try resolveAPI(operation: operation, accountId: accountId, threadId: threadId)
        let originalLabels = try await labelSnapshot(accountId: accountId, threadId: threadId)
        logStart(operation: operation, accountId: accountId, threadId: threadId)

        try await db.dbQueue.write { dbConn in
            for labelId in removeLabelIds {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId).delete(dbConn)
            }
            for labelId in addLabelIds {
                let record = ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId)
                try record.insert(dbConn, onConflict: .ignore)
            }
        }

        do {
            _ = try await api.modifyThread(
                id: threadId,
                addLabelIds: addLabelIds,
                removeLabelIds: removeLabelIds
            )
            logSuccess(operation: operation, accountId: accountId, threadId: threadId)
        } catch {
            let mutationError = MailMutationError.wrap(operation: operation, error: error)
            try? await db.dbQueue.write { dbConn in
                try restoreLabelSnapshot(originalLabels, accountId: accountId, threadId: threadId, db: dbConn)
            }
            logFailure(
                operation: operation,
                accountId: accountId,
                threadId: threadId,
                category: mutationError.category
            )
            throw mutationError
        }
    }

    // MARK: - Snapshots

    private struct ReadSnapshot: Sendable {
        let labels: Set<String>
        let hasUnread: Int?
        let messageFlags: [String: Int]
    }

    private func labelSnapshot(accountId: String, threadId: String) async throws -> Set<String> {
        try await db.dbQueue.read { dbConn in
            let rows = try ThreadLabelRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                .fetchAll(dbConn)
            return Set(rows.map(\.labelId))
        }
    }

    private func readSnapshot(accountId: String, threadId: String) async throws -> ReadSnapshot {
        try await db.dbQueue.read { dbConn in
            let labels = try ThreadLabelRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                .fetchAll(dbConn)
                .map(\.labelId)

            let hasUnread = try Int.fetchOne(
                dbConn,
                sql: "SELECT has_unread FROM thread WHERE account_id = ? AND id = ?",
                arguments: [accountId, threadId]
            )

            let messages = try Row.fetchAll(
                dbConn,
                sql: "SELECT id, flags FROM message WHERE account_id = ? AND thread_id = ?",
                arguments: [accountId, threadId]
            )
            let flags = Dictionary(uniqueKeysWithValues: messages.map { row in
                (row["id"] as String, row["flags"] as Int)
            })

            return ReadSnapshot(labels: Set(labels), hasUnread: hasUnread, messageFlags: flags)
        }
    }

    private nonisolated func restoreLabelSnapshot(
        _ labels: Set<String>,
        accountId: String,
        threadId: String,
        db dbConn: Database
    ) throws {
        try dbConn.execute(
            sql: "DELETE FROM thread_label WHERE account_id = ? AND thread_id = ?",
            arguments: [accountId, threadId]
        )
        for labelId in labels {
            try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId)
                .insert(dbConn, onConflict: .ignore)
        }
    }

    private nonisolated func restoreReadSnapshot(
        _ snapshot: ReadSnapshot,
        accountId: String,
        threadId: String,
        db dbConn: Database
    ) throws {
        if snapshot.labels.contains("UNREAD") {
            try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD")
                .insert(dbConn, onConflict: .ignore)
        } else {
            try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD").delete(dbConn)
        }

        if let hasUnread = snapshot.hasUnread {
            try dbConn.execute(
                sql: "UPDATE thread SET has_unread = ? WHERE account_id = ? AND id = ?",
                arguments: [hasUnread, accountId, threadId]
            )
        }

        for (messageId, flags) in snapshot.messageFlags {
            try dbConn.execute(
                sql: "UPDATE message SET flags = ? WHERE account_id = ? AND id = ?",
                arguments: [flags, accountId, messageId]
            )
        }
    }

    // MARK: - Provider and logging

    private func resolveAPI(
        operation: MailMutationOperation,
        accountId: String,
        threadId: String
    ) throws -> any GmailAPI {
        do {
            return try apiFactory(accountId)
        } catch {
            let mutationError = MailMutationError.wrap(operation: operation, error: error)
            logFailure(
                operation: operation,
                accountId: accountId,
                threadId: threadId,
                category: mutationError.category
            )
            throw mutationError
        }
    }

    private nonisolated func logStart(
        operation: MailMutationOperation,
        accountId: String,
        threadId: String
    ) {
        Self.logger.info(
            "Gmail mutation started operation=\(operation.rawValue, privacy: .public) account=\(accountId, privacy: .public) thread=\(threadId, privacy: .public)"
        )
    }

    private nonisolated func logSuccess(
        operation: MailMutationOperation,
        accountId: String,
        threadId: String
    ) {
        Self.logger.info(
            "Gmail mutation succeeded operation=\(operation.rawValue, privacy: .public) account=\(accountId, privacy: .public) thread=\(threadId, privacy: .public)"
        )
    }

    private nonisolated func logFailure(
        operation: MailMutationOperation,
        accountId: String,
        threadId: String,
        category: MailProviderErrorCategory
    ) {
        Self.logger.error(
            "Gmail mutation failed operation=\(operation.rawValue, privacy: .public) account=\(accountId, privacy: .public) thread=\(threadId, privacy: .public) category=\(category.rawValue, privacy: .public)"
        )
    }
}
