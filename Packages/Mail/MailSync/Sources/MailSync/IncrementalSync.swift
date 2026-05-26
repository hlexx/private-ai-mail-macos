import Foundation
import GRDB
import MailDomain
import MailProviders
import Persistence

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

        var checkpointHistoryId = historyId
        var pageToken: String?
        var affectedThreadIds = Set<String>()

        repeat {
            let response = try await api.listHistory(
                startHistoryId: historyId,
                pageToken: pageToken
            )

            for record in response.history ?? [] {
                // Process added messages
                for added in record.messagesAdded ?? [] {
                    let msg = added.message
                    affectedThreadIds.insert(msg.threadId)
                }

                // Process deleted messages — just track affected threads;
                // the re-fetch below will reconcile the correct state.
                for deleted in record.messagesDeleted ?? [] {
                    affectedThreadIds.insert(deleted.message.threadId)
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
                checkpointHistoryId = newHistoryId
            }
            pageToken = response.nextPageToken
        } while pageToken != nil

        // Re-fetch affected threads to get current state
        for threadId in affectedThreadIds {
            do {
                let dto = try await api.getThread(id: threadId, format: .full)
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
            historyId: checkpointHistoryId,
            db: db
        )
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

            // Delete existing messages and re-insert; attachment FK cascade handles cleanup
            try MessageRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == mapped.id)
                .deleteAll(dbConn)

            var threadLabelIds = Set<String>()

            for dtoMsg in dto.messages ?? [] {
                let (msg, labelIds) = GmailMapper.mapMessageWithLabels(dtoMsg, accountId: accountId)
                try makeMessageRecord(from: msg, accountId: accountId)
                    .save(dbConn, onConflict: .replace)

                for att in msg.attachments {
                    try makeAttachmentRecord(from: att, messageId: msg.id, accountId: accountId)
                        .save(dbConn, onConflict: .replace)
                }

                threadLabelIds.formUnion(labelIds)
            }

            // Replace thread_label rows for this thread+account
            try ThreadLabelRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == dto.id)
                .deleteAll(dbConn)
            for labelId in threadLabelIds {
                try ThreadLabelRecord(accountId: accountId, threadId: dto.id, labelId: labelId)
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
            // Delete thread_label rows (no FK cascade from thread), messages (FK cascade
            // removes their attachments), then the thread record itself.
            try ThreadLabelRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                .deleteAll(dbConn)
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
