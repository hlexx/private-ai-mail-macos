import GRDB
import MailProviders
import Persistence

enum ThreadPersistence {
    @DatabaseActor
    static func upsertThread(
        _ dto: GmailDTO.Thread,
        accountId: String,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            try upsertThread(dto, accountId: accountId, dbConn: dbConn)
        }
    }

    @DatabaseActor
    static func upsertThreads(
        _ dtoThreads: [GmailDTO.Thread],
        accountId: String,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            for dto in dtoThreads {
                try upsertThread(dto, accountId: accountId, dbConn: dbConn)
            }
        }
    }

    private static func upsertThread(
        _ dto: GmailDTO.Thread,
        accountId: String,
        dbConn: Database
    ) throws {
        let mapped = GmailMapper.mapThread(dto, accountId: accountId)
        try makeThreadRecord(from: mapped, accountId: accountId)
            .save(dbConn, onConflict: .replace)

        let incomingMessageIds = Set((dto.messages ?? []).map(\.id))
        let existingMessageIds = try String.fetchAll(
            dbConn,
            sql: """
                SELECT id FROM message
                WHERE account_id = ? AND thread_id = ?
                """,
            arguments: [accountId, mapped.id]
        )
        for messageId in existingMessageIds where !incomingMessageIds.contains(messageId) {
            try SearchIndexMaintenance.deleteMessage(accountId: accountId, messageId: messageId, db: dbConn)
            try MessageRecord.deleteOne(dbConn, key: ["account_id": accountId, "id": messageId])
        }

        var threadLabelIds = Set<String>()
        for dtoMsg in dto.messages ?? [] {
            let (msg, labelIds) = GmailMapper.mapMessageWithLabels(dtoMsg, accountId: accountId)
            try upsertMessageRecord(makeMessageRecord(from: msg, accountId: accountId), db: dbConn)

            let incomingAttachmentIds = Set(msg.attachments.map(\.id))
            let existingAttachmentIds = try String.fetchAll(
                dbConn,
                sql: """
                    SELECT id FROM attachment
                    WHERE account_id = ? AND message_id = ?
                    """,
                arguments: [accountId, msg.id]
            )
            for attachmentId in existingAttachmentIds where !incomingAttachmentIds.contains(attachmentId) {
                try AttachmentRecord.deleteOne(
                    dbConn,
                    key: ["account_id": accountId, "message_id": msg.id, "id": attachmentId]
                )
            }

            for att in msg.attachments {
                try upsertAttachmentRecord(
                    makeAttachmentRecord(from: att, messageId: msg.id, accountId: accountId),
                    db: dbConn
                )
            }

            threadLabelIds.formUnion(labelIds)
        }

        try ThreadLabelRecord
            .filter(Column("account_id") == accountId && Column("thread_id") == dto.id)
            .deleteAll(dbConn)
        for labelId in threadLabelIds {
            try ThreadLabelRecord(accountId: accountId, threadId: dto.id, labelId: labelId)
                .save(dbConn, onConflict: .replace)
        }
        try SearchIndexMaintenance.upsertMessages(
            accountId: accountId,
            messageIds: incomingMessageIds,
            db: dbConn
        )
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
}
