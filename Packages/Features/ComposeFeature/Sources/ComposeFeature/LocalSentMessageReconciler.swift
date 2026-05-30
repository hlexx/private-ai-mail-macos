import Foundation
import GRDB
import MailDomain
import MailProviders
import Persistence

struct LocalSentMessageReconciler: Sendable {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func reconcileGmailDirectSend(
        draft: ComposeDraft,
        sent: GmailDTO.SentMessage,
        rfcMessageID: String,
        sentAt: Date
    ) async throws -> SentEcho {
        var labelIDs = Set(sent.labelIds ?? [])
        labelIDs.insert("SENT")

        return try await reconcile(
            SentMessageReconciliationInput(
                messageID: sent.id,
                threadID: sent.threadId,
                accountID: draft.accountID,
                messageIDHeader: rfcMessageID,
                from: draft.from,
                to: draft.to,
                cc: draft.cc,
                subject: draft.subject,
                bodyText: draft.body,
                bodyHTML: nil,
                labelIDs: labelIDs,
                isNewThread: draft.replyContext == nil,
                sentAt: sentAt
            )
        )
    }

    func reconcileQueuedSend(
        item: QueuedOutgoingMessage,
        result: ProviderSendResult
    ) async throws -> SentEcho {
        let messageID = result.providerMessageID
            ?? item.providerMessageID
            ?? result.rfcMessageID
            ?? item.rfcMessageID
            ?? item.id.rawValue
        let threadID = result.providerThreadID
            ?? item.providerThreadID
            ?? item.threadID
            ?? messageID

        return try await reconcile(
            SentMessageReconciliationInput(
                messageID: messageID,
                threadID: threadID,
                accountID: item.accountID,
                messageIDHeader: result.rfcMessageID ?? item.rfcMessageID,
                from: item.from,
                to: item.to,
                cc: item.cc,
                subject: item.subject,
                bodyText: item.bodyText,
                bodyHTML: item.bodyHTML,
                labelIDs: ["SENT"],
                isNewThread: item.threadID == nil,
                sentAt: result.sentAt
            )
        )
    }

    @DatabaseActor
    private func reconcile(_ input: SentMessageReconciliationInput) throws -> SentEcho {
        let sentAtUnix = Int(input.sentAt.timeIntervalSince1970)
        let record = MessageRecord(
            id: input.messageID,
            threadId: input.threadID,
            accountId: input.accountID,
            messageIdHeader: input.messageIDHeader,
            fromAddr: Self.formatAddress(input.from),
            toAddr: Self.formatAddressList(input.to),
            ccAddr: input.cc.isEmpty ? nil : Self.formatAddressList(input.cc),
            sentAt: sentAtUnix,
            snippet: String((input.bodyText ?? input.bodyHTML ?? "").prefix(200)),
            bodyHtml: input.bodyHTML,
            bodyText: input.bodyText,
            flags: MessageRecord.sentByMe | MessageRecord.read
        )

        try db.write { dbConn in
            let messageAlreadyExists = try MessageRecord.fetchOne(
                dbConn,
                key: ["account_id": record.accountId, "id": record.id]
            ) != nil

            try record.save(dbConn, onConflict: .replace)

            for labelID in input.labelIDs {
                try ThreadLabelRecord(
                    accountId: input.accountID,
                    threadId: input.threadID,
                    labelId: labelID
                ).save(dbConn, onConflict: .replace)
            }

            if input.isNewThread {
                let thread = ThreadRecord(
                    id: input.threadID,
                    accountId: input.accountID,
                    subject: input.subject,
                    snippet: String(record.snippet?.prefix(200) ?? ""),
                    lastMessageAt: sentAtUnix,
                    messageCount: 1
                )
                try thread.save(dbConn, onConflict: .replace)
            } else if var existing = try ThreadRecord
                .filter(Column("id") == input.threadID && Column("account_id") == input.accountID)
                .fetchOne(dbConn) {
                existing.lastMessageAt = sentAtUnix
                if !messageAlreadyExists {
                    existing.messageCount += 1
                }
                existing.snippet = record.snippet
                try existing.update(dbConn)
            }
        }

        return SentEcho(messageID: input.messageID, threadID: input.threadID, sentAt: input.sentAt)
    }

    private static func formatAddress(_ address: Address) -> String {
        if let name = address.name {
            return "\(name) <\(address.email)>"
        }
        return address.email
    }

    private static func formatAddressList(_ addresses: [Address]) -> String {
        addresses.map { formatAddress($0) }.joined(separator: ", ")
    }
}

private struct SentMessageReconciliationInput: Sendable {
    let messageID: String
    let threadID: String
    let accountID: String
    let messageIDHeader: String?
    let from: Address
    let to: [Address]
    let cc: [Address]
    let subject: String
    let bodyText: String?
    let bodyHTML: String?
    let labelIDs: Set<String>
    let isNewThread: Bool
    let sentAt: Date
}
