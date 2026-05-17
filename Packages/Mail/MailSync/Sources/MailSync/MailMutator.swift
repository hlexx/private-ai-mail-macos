import GRDB
import MailProviders
import Persistence

public actor MailMutator {
    private let db: AppDatabase
    private let apiFactory: @Sendable (String) -> any GmailAPI

    public init(db: AppDatabase, apiFactory: @Sendable @escaping (String) -> any GmailAPI) {
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
        try await mutateLabels(
            threadId: threadId,
            accountId: accountId,
            addLabelIds: read ? [] : ["UNREAD"],
            removeLabelIds: read ? ["UNREAD"] : []
        )
        let readFlag = MessageRecord.read
        try await db.dbQueue.write { dbConn in
            if read {
                try dbConn.execute(
                    sql: "UPDATE message SET flags = flags | ? WHERE thread_id = ?",
                    arguments: [readFlag, threadId]
                )
            } else {
                try dbConn.execute(
                    sql: "UPDATE message SET flags = flags & ~? WHERE thread_id = ?",
                    arguments: [readFlag, threadId]
                )
            }
            try dbConn.execute(
                sql: "UPDATE thread SET has_unread = ? WHERE id = ?",
                arguments: [read ? 0 : 1, threadId]
            )
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
        // 1. Optimistic local update
        try await db.dbQueue.write { dbConn in
            for labelId in removeLabelIds {
                try ThreadLabelRecord(threadId: threadId, labelId: labelId).delete(dbConn)
            }
            for labelId in addLabelIds {
                let record = ThreadLabelRecord(threadId: threadId, labelId: labelId)
                try record.insert(dbConn, onConflict: .ignore)
            }
        }

        // 2. API call
        do {
            let api = apiFactory(accountId)
            _ = try await api.modifyThread(
                id: threadId,
                addLabelIds: addLabelIds,
                removeLabelIds: removeLabelIds
            )
        } catch {
            // 3. Rollback on failure
            try? await db.dbQueue.write { dbConn in
                for labelId in addLabelIds {
                    try ThreadLabelRecord(threadId: threadId, labelId: labelId).delete(dbConn)
                }
                for labelId in removeLabelIds {
                    let record = ThreadLabelRecord(threadId: threadId, labelId: labelId)
                    try record.insert(dbConn, onConflict: .ignore)
                }
            }
            throw error
        }
    }
}
