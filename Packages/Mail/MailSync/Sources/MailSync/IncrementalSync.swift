import Foundation
import MailProviders
import MailDomain
import Persistence
import GRDB

enum IncrementalSync {
    static func run(
        accountId: String,
        api: any GmailAPI,
        db: AppDatabase,
        onThreadUpserted: @Sendable (String) async -> Void
    ) async throws {
        let startHistoryId = try db.read { dbConn -> String? in
            let record = try SyncStateRecord.fetchOne(dbConn, key: ["account_id": accountId])
            return record?.historyId
        }

        guard let historyId = startHistoryId else {
            throw SyncError.historyExpired
        }

        var currentHistoryId = historyId
        var pageToken: String? = nil
        var affectedThreadIds = Set<String>()

        repeat {
            let response = try await api.listHistory(
                startHistoryId: currentHistoryId,
                pageToken: pageToken
            )

            for record in response.history ?? [] {
                // Process added messages
                for added in record.messagesAdded ?? [] {
                    let msg = added.message
                    affectedThreadIds.insert(msg.threadId)
                }

                // Process deleted messages
                for deleted in record.messagesDeleted ?? [] {
                    let msg = deleted.message
                    try await deleteMessage(
                        messageId: msg.id,
                        threadId: msg.threadId,
                        accountId: accountId,
                        db: db
                    )
                    affectedThreadIds.insert(msg.threadId)
                }

                // Process label changes
                for labelAdded in record.labelsAdded ?? [] {
                    affectedThreadIds.insert(labelAdded.message.threadId)
                }
                for labelRemoved in record.labelsRemoved ?? [] {
                    affectedThreadIds.insert(labelRemoved.message.threadId)
                }
            }

            if let newHistoryId = response.historyId {
                currentHistoryId = newHistoryId
            }
            pageToken = response.nextPageToken
        } while pageToken != nil

        // Re-fetch affected threads to get current state
        for threadId in affectedThreadIds {
            do {
                let dto = try await api.getThread(id: threadId, format: .metadata)
                try await upsertThread(dto, accountId: accountId, db: db)
                await onThreadUpserted(threadId)
            } catch let error as GmailAPIError {
                // Thread may have been deleted entirely - that's OK
                if case .serverError(statusCode: 404) = error {
                    try await removeThread(threadId: threadId, accountId: accountId, db: db)
                } else {
                    throw error
                }
            }
        }

        // Update sync state with new history ID
        try await updateHistoryId(
            accountId: accountId,
            historyId: currentHistoryId,
            db: db
        )
    }

    @DatabaseActor
    private static func deleteMessage(
        messageId: String,
        threadId: String,
        accountId: String,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            try MessageRecord.deleteOne(dbConn, key: ["account_id": accountId, "id": messageId])

            // Update thread message count
            let count = try MessageRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                .fetchCount(dbConn)
            if count == 0 {
                try ThreadRecord.deleteOne(dbConn, key: ["account_id": accountId, "id": threadId])
            } else {
                if var thread = try ThreadRecord.fetchOne(dbConn, key: ["account_id": accountId, "id": threadId]) {
                    thread.messageCount = count
                    try thread.update(dbConn)
                }
            }
        }
    }

    @DatabaseActor
    private static func upsertThread(
        _ dto: GmailDTO.Thread,
        accountId: String,
        db: AppDatabase
    ) throws {
        let mapped = GmailMapper.mapThread(dto, accountId: accountId)
        try db.write { dbConn in
            try makeThreadRecord(from: mapped, accountId: accountId)
                .save(dbConn, onConflict: .replace)

            // Delete existing messages for this thread and re-insert
            try MessageRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == mapped.id)
                .deleteAll(dbConn)

            for msg in mapped.messages {
                try makeMessageRecord(from: msg, accountId: accountId)
                    .save(dbConn, onConflict: .replace)
            }
        }
    }

    @DatabaseActor
    private static func removeThread(
        threadId: String,
        accountId: String,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            try MessageRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                .deleteAll(dbConn)
            try ThreadRecord.deleteOne(dbConn, key: ["account_id": accountId, "id": threadId])
        }
    }

    @DatabaseActor
    private static func updateHistoryId(
        accountId: String,
        historyId: String,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            if var syncState = try SyncStateRecord.fetchOne(dbConn, key: ["account_id": accountId]) {
                syncState.historyId = historyId
                try syncState.update(dbConn)
            }
        }
    }
}
