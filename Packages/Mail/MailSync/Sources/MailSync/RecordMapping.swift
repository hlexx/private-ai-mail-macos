import Foundation
import MailDomain
import MailProviders
import Persistence

func formatAddress(_ addr: Address) -> String {
    if let name = addr.name {
        return "\(name) <\(addr.email)>"
    }
    return addr.email
}

func makeThreadRecord(from mapped: MailDomain.Thread, accountId: String) -> ThreadRecord {
    ThreadRecord(
        id: mapped.id,
        accountId: accountId,
        subject: mapped.subject,
        snippet: mapped.snippet,
        lastMessageAt: Int(mapped.lastMessageAt.timeIntervalSince1970),
        messageCount: mapped.messageCount,
        hasUnread: mapped.hasUnread ? 1 : 0
    )
}

func makeMessageRecord(from msg: MailDomain.Message, accountId: String) -> MessageRecord {
    MessageRecord(
        id: msg.id,
        threadId: msg.threadId,
        accountId: accountId,
        messageIdHeader: msg.messageIdHeader,
        fromAddr: msg.from.map(formatAddress),
        toAddr: msg.to.map(formatAddress).joined(separator: ", "),
        ccAddr: msg.cc.map(formatAddress).joined(separator: ", "),
        sentAt: Int(msg.sentAt.timeIntervalSince1970),
        snippet: msg.snippet,
        bodyHtml: msg.bodyHTML,
        bodyText: msg.bodyText,
        flags: msg.isUnread ? 1 : 0
    )
}

func makeAttachmentRecord(from att: MailDomain.Attachment, messageId: String, accountId: String) -> AttachmentRecord {
    AttachmentRecord(
        id: att.id,
        messageId: messageId,
        accountId: accountId,
        filename: att.filename,
        mime: att.mimeType,
        sizeBytes: att.sizeBytes
    )
}
