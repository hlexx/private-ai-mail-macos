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
            try MessageRecord.deleteOne(dbConn, key: ["account_id": accountId, "id": messageId])
        }

        var threadLabelIds = Set<String>()
        for dtoMsg in dto.messages ?? [] {
            let (msg, labelIds) = GmailMapper.mapMessageWithLabels(dtoMsg, accountId: accountId)
            try makeMessageRecord(from: msg, accountId: accountId)
                .save(dbConn, onConflict: .replace)

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
                try makeAttachmentRecord(from: att, messageId: msg.id, accountId: accountId)
                    .save(dbConn, onConflict: .replace)
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
    }
}
