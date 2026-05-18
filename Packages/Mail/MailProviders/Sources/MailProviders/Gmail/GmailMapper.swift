import Foundation
import MailDomain

public enum GmailMapper {
    public static func mapMessage(_ dto: GmailDTO.Message, accountId: String) -> MailDomain.Message {
        let headers = dto.payload?.headers ?? []
        let from = header("From", in: headers).flatMap { Address(rfc822: $0) }
        let to = header("To", in: headers).map { parseAddressList($0) } ?? []
        let cc = header("Cc", in: headers).map { parseAddressList($0) } ?? []
        let messageIdHeader = header("Message-Id", in: headers) ?? header("Message-ID", in: headers)
        let sentAt: Date
        if let internalDate = dto.internalDate, let ms = Double(internalDate) {
            sentAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            sentAt = Date.distantPast
        }
        let isUnread = dto.labelIds?.contains("UNREAD") ?? false
        let isSentByMe = dto.labelIds?.contains("SENT") ?? false
        let (bodyText, bodyHTML) = extractBodies(from: dto.payload)
        let attachments = extractAttachments(from: dto.payload, messageId: dto.id)

        return MailDomain.Message(
            id: dto.id,
            threadId: dto.threadId,
            accountId: accountId,
            messageIdHeader: messageIdHeader,
            from: from,
            to: to,
            cc: cc,
            sentAt: sentAt,
            snippet: dto.snippet,
            bodyText: bodyText,
            bodyHTML: bodyHTML,
            attachments: attachments,
            isUnread: isUnread,
            isSentByMe: isSentByMe
        )
    }

    public static func mapMessageWithLabels(_ dto: GmailDTO.Message, accountId: String) -> (message: MailDomain.Message, labelIds: [String]) {
        let message = mapMessage(dto, accountId: accountId)
        let labelIds = dto.labelIds ?? []
        return (message, labelIds)
    }

    public static func mapThread(_ dto: GmailDTO.Thread, accountId: String) -> MailDomain.Thread {
        let messages = (dto.messages ?? []).map { mapMessage($0, accountId: accountId) }
        let lastMessageAt = messages.map(\.sentAt).max() ?? Date.distantPast
        let subject: String? = {
            let headers = dto.messages?.first?.payload?.headers ?? []
            return header("Subject", in: headers)
        }()
        let snippet = dto.messages?.last?.snippet
        let hasUnread = messages.contains { $0.isUnread }

        return MailDomain.Thread(
            id: dto.id,
            accountId: accountId,
            subject: subject,
            snippet: snippet,
            lastMessageAt: lastMessageAt,
            messageCount: messages.count,
            hasUnread: hasUnread,
            messages: messages
        )
    }

    private static func header(_ name: String, in headers: [GmailDTO.MessagePartHeader]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func parseAddressList(_ raw: String) -> [Address] {
        raw.split(separator: ",").compactMap { Address(rfc822: String($0)) }
    }

    private static func extractBodies(from part: GmailDTO.MessagePart?) -> (text: String?, html: String?) {
        guard let part else { return (nil, nil) }
        var text: String?
        var html: String?
        collectBodies(part: part, text: &text, html: &html)
        return (text, html)
    }

    private static func collectBodies(part: GmailDTO.MessagePart, text: inout String?, html: inout String?) {
        if let mime = part.mimeType {
            if mime == "text/plain", text == nil, let data = part.body?.data {
                text = decodeBase64URL(data)
            } else if mime == "text/html", html == nil, let data = part.body?.data {
                html = decodeBase64URL(data)
            }
        }
        for child in part.parts ?? [] {
            collectBodies(part: child, text: &text, html: &html)
        }
    }

    private static func extractAttachments(from part: GmailDTO.MessagePart?, messageId: String) -> [Attachment] {
        guard let part else { return [] }
        var result: [Attachment] = []
        collectAttachments(part: part, messageId: messageId, result: &result)
        return result
    }

    private static func collectAttachments(part: GmailDTO.MessagePart, messageId: String, result: inout [Attachment]) {
        let partContentId = part.headers?.first {
            $0.name.caseInsensitiveCompare("Content-ID") == .orderedSame
        }?.value
        let normalizedCid = partContentId?
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))

        if let attachmentId = part.body?.attachmentId, let filename = part.filename, !filename.isEmpty {
            result.append(Attachment(
                id: attachmentId,
                messageId: messageId,
                filename: filename,
                mimeType: part.mimeType,
                sizeBytes: part.body?.size,
                contentId: normalizedCid
            ))
        } else if let cid = normalizedCid, !cid.isEmpty,
                  let mime = part.mimeType, mime.hasPrefix("image/"),
                  let bodyData = part.body?.data {
            let id = "inline_\(cid)"
            let base64 = base64URLToStandard(bodyData)
            result.append(Attachment(
                id: id,
                messageId: messageId,
                filename: nil,
                mimeType: mime,
                sizeBytes: part.body?.size,
                contentId: cid,
                inlineData: base64
            ))
        }
        for child in part.parts ?? [] {
            collectAttachments(part: child, messageId: messageId, result: &result)
        }
    }

    private static func base64URLToStandard(_ encoded: String) -> String {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }

    private static func decodeBase64URL(_ encoded: String) -> String? {
        let base64 = base64URLToStandard(encoded)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
