import Foundation
import GRDB
import MailDomain
import MailProviders
import Persistence

enum ThreadPersistence {
    static func reconcileThread(
        _ dto: GmailDTO.Thread,
        accountId: String,
        db dbConn: Database
    ) throws {
        let mapped = GmailMapper.mapThread(dto, accountId: accountId)
        try makeThreadRecord(from: mapped, accountId: accountId)
            .save(dbConn, onConflict: .replace)

        var incomingMessageIds = Set<String>()
        var threadLabelIds = Set<String>()

        for dtoMsg in dto.messages ?? [] {
            let (msg, labelIds) = GmailMapper.mapMessageWithLabels(dtoMsg, accountId: accountId)
            incomingMessageIds.insert(msg.id)
            threadLabelIds.formUnion(labelIds)

            try makeMessageRecord(from: msg, accountId: accountId)
                .save(dbConn, onConflict: .replace)

            try reconcileAttachments(msg.attachments, messageId: msg.id, accountId: accountId, db: dbConn)
        }

        try deleteMessagesMissingFromFetchedThread(
            incomingMessageIds,
            threadId: dto.id,
            accountId: accountId,
            db: dbConn
        )
        try replaceThreadLabels(threadLabelIds, threadId: dto.id, accountId: accountId, db: dbConn)
    }

    private static func reconcileAttachments(
        _ attachments: [MailDomain.Attachment],
        messageId: String,
        accountId: String,
        db dbConn: Database
    ) throws {
        let incomingAttachmentIds = Set(attachments.map(\.id))

        for attachment in attachments {
            try makeAttachmentRecord(from: attachment, messageId: messageId, accountId: accountId)
                .save(dbConn, onConflict: .replace)
        }

        try deleteAttachmentsMissingFromFetchedMessage(
            incomingAttachmentIds,
            messageId: messageId,
            accountId: accountId,
            db: dbConn
        )
    }

    private static func deleteMessagesMissingFromFetchedThread(
        _ incomingMessageIds: Set<String>,
        threadId: String,
        accountId: String,
        db dbConn: Database
    ) throws {
        var request = MessageRecord
            .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
        if !incomingMessageIds.isEmpty {
            request = request.filter(!incomingMessageIds.contains(Column("id")))
        }
        try request.deleteAll(dbConn)
    }

    private static func deleteAttachmentsMissingFromFetchedMessage(
        _ incomingAttachmentIds: Set<String>,
        messageId: String,
        accountId: String,
        db dbConn: Database
    ) throws {
        var request = AttachmentRecord
            .filter(Column("account_id") == accountId && Column("message_id") == messageId)
        if !incomingAttachmentIds.isEmpty {
            request = request.filter(!incomingAttachmentIds.contains(Column("id")))
        }
        try request.deleteAll(dbConn)
    }

    private static func replaceThreadLabels(
        _ labelIds: Set<String>,
        threadId: String,
        accountId: String,
        db dbConn: Database
    ) throws {
        try ThreadLabelRecord
            .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
            .deleteAll(dbConn)
        for labelId in labelIds {
            try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId)
                .save(dbConn, onConflict: .replace)
        }
    }
}
