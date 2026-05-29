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

        var currentHistoryId = historyId
        var pageToken: String?
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
                currentHistoryId = newHistoryId
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
            historyId: currentHistoryId,
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

            var threadLabelIds = Set<String>()
            var currentMessageIds = Set<String>()
            var currentAttachmentIdsByMessage: [String: Set<String>] = [:]

            for dtoMsg in dto.messages ?? [] {
                let (msg, labelIds) = GmailMapper.mapMessageWithLabels(dtoMsg, accountId: accountId)
                currentMessageIds.insert(msg.id)
                try upsertMessageRecord(makeMessageRecord(from: msg, accountId: accountId), db: dbConn)

                for att in msg.attachments {
                    currentAttachmentIdsByMessage[msg.id, default: []].insert(att.id)
                    try upsertAttachmentRecord(
                        makeAttachmentRecord(from: att, messageId: msg.id, accountId: accountId),
                        db: dbConn
                    )
                }

                threadLabelIds.formUnion(labelIds)
            }

            let existingMessages = try MessageRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == mapped.id)
                .fetchAll(dbConn)

            for message in existingMessages where !currentMessageIds.contains(message.id) {
                try message.delete(dbConn)
            }

            for messageId in currentMessageIds {
                let currentAttachmentIds = currentAttachmentIdsByMessage[messageId] ?? []
                let existingAttachments = try AttachmentRecord
                    .filter(Column("account_id") == accountId && Column("message_id") == messageId)
                    .fetchAll(dbConn)
                for attachment in existingAttachments where !currentAttachmentIds.contains(attachment.id) {
                    try attachment.delete(dbConn)
                }
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

    private static func upsertMessageRecord(_ record: MessageRecord, db: Database) throws {
        if try MessageRecord.fetchOne(db, key: ["account_id": record.accountId, "id": record.id]) != nil {
            try record.update(db)
        } else {
            try record.insert(db)
        }
    }

    private static func upsertAttachmentRecord(_ record: AttachmentRecord, db: Database) throws {
        if try AttachmentRecord.fetchOne(
            db,
            key: ["account_id": record.accountId, "message_id": record.messageId, "id": record.id]
        ) != nil {
            try record.update(db)
        } else {
            try record.insert(db)
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
