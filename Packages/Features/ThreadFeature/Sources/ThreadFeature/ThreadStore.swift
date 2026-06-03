import Foundation
import GRDB
import Observation
import Persistence

public struct InlineAttachment: Sendable {
    public let contentId: String
    public let mime: String
    public let dataBase64: String
}

public struct MessageRow: Identifiable, Sendable {
    public let id: String
    public let threadId: String
    public let messageIdHeader: String?
    public let fromAddr: String
    public let toAddr: String?
    public let ccAddr: String?
    public let sentAt: Date
    public let snippet: String
    public let bodyText: String
    public let bodyHtml: String?
    public let flags: Int
    public let inlineAttachments: [InlineAttachment]

    public var isSentByMe: Bool {
        (flags & MessageRecord.sentByMe) != 0
    }

    /// Best available plain text for language detection and translation input.
    /// Falls back: bodyText -> HTML-stripped -> snippet.
    @MainActor public var bestPlainText: String {
        if let text = bodyHtml, !text.isEmpty, bodyText == snippet || bodyText.isEmpty {
            return MessageBodyView.htmlToPlainText(text) ?? bodyText
        }
        return bodyText
    }

    public init(record: MessageRecord, inlineAttachments: [InlineAttachment] = []) {
        self.id = record.id
        self.threadId = record.threadId
        self.messageIdHeader = record.messageIdHeader
        self.fromAddr = record.fromAddr ?? "(unknown)"
        self.toAddr = record.toAddr
        self.ccAddr = record.ccAddr
        self.sentAt = Date(timeIntervalSince1970: TimeInterval(record.sentAt))
        self.snippet = record.snippet ?? ""
        self.bodyText = record.bodyText ?? record.snippet ?? ""
        self.bodyHtml = record.bodyHtml
        self.flags = record.flags
        self.inlineAttachments = inlineAttachments
    }

    public var senderName: String {
        Self.extractName(from: fromAddr)
    }

    static func extractName(from addr: String) -> String {
        let trimmed = addr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "?" }
        if let angleBracket = trimmed.firstIndex(of: "<") {
            let name = trimmed[trimmed.startIndex..<angleBracket]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
        }
        if let at = trimmed.firstIndex(of: "@") {
            return String(trimmed[trimmed.startIndex..<at])
        }
        return trimmed
    }
}

public struct AttachmentInfo: Identifiable, Sendable {
    public let id: String
    public let messageId: String
    public let accountId: String
    public let filename: String
    public let sizeBytes: Int?
    public let mime: String?
    public let cache: AttachmentCacheInfo?

    public init(record: AttachmentRecord, cache: AttachmentCacheInfo? = nil) {
        self.id = record.id
        self.messageId = record.messageId
        self.accountId = record.accountId
        self.filename = record.filename ?? "attachment"
        self.sizeBytes = record.sizeBytes
        self.mime = record.mime
        self.cache = cache
    }

    public init(id: String, messageId: String = "", accountId: String = "", filename: String, sizeBytes: Int?, mime: String?, cache: AttachmentCacheInfo? = nil) {
        self.id = id
        self.messageId = messageId
        self.accountId = accountId
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.mime = mime
        self.cache = cache
    }

    public var formattedSize: String {
        guard let bytes = sizeBytes else { return "" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    public var hasDownloadIdentity: Bool {
        !id.isEmpty && !messageId.isEmpty && !accountId.isEmpty
    }
}

public struct AttachmentCacheInfo: Sendable, Equatable {
    public let relativePath: String
    public let byteCount: Int
    public let sha256: String
    public let storedAt: Int

    public init(relativePath: String, byteCount: Int, sha256: String, storedAt: Int) {
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.storedAt = storedAt
    }

    public init(record: AttachmentBlobRecord) {
        self.relativePath = record.relativePath
        self.byteCount = record.byteCount
        self.sha256 = record.sha256
        self.storedAt = record.storedAt
    }
}

@Observable
@MainActor
public final class ThreadStore {
    public private(set) var messages: [MessageRow] = []
    public private(set) var subject: String = ""
    public private(set) var messageCount: Int = 0
    public private(set) var attachments: [AttachmentInfo] = []
    public private(set) var isStarred: Bool = false
    public private(set) var observedThreadId: String?
    public private(set) var observedAccountId: String?
    public var accountEmail: String = ""

    public var hasAttachment: Bool { !attachments.isEmpty }

    public var senderName: String {
        messages.first { $0.senderName != "?" }?.senderName ?? "?"
    }

    private let db: AppDatabase
    private var observationTask: Task<Void, Never>?

    public init(db: AppDatabase) {
        self.db = db
    }

    public func observe(threadId: String, accountId: String) {
        observationTask?.cancel()
        observedThreadId = threadId
        observedAccountId = accountId
        observationTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db in
                let thread = try ThreadRecord
                    .filter(Column("id") == threadId && Column("account_id") == accountId)
                    .fetchOne(db)

                let messages = try MessageRecord
                    .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                    .order(Column("sent_at").asc)
                    .fetchAll(db)

                let isStarred = try ThreadLabelRecord
                    .filter(Column("account_id") == accountId && Column("thread_id") == threadId && Column("label_id") == "STARRED")
                    .fetchOne(db) != nil

                let messageIds = messages.map(\.id)
                let attachments: [AttachmentRecord]
                if messageIds.isEmpty {
                    attachments = []
                } else {
                    attachments = try AttachmentRecord
                        .filter(messageIds.contains(Column("message_id")) && Column("account_id") == accountId)
                        .fetchAll(db)
                }

                let blobs: [AttachmentBlobRecord]
                if messageIds.isEmpty {
                    blobs = []
                } else {
                    blobs = try AttachmentBlobRecord
                        .filter(messageIds.contains(Column("message_id")) && Column("account_id") == accountId)
                        .fetchAll(db)
                }

                return (thread, messages, attachments, blobs, isStarred)
            }
            do {
                for try await (thread, records, attRecords, blobRecords, starred) in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled, let self else { return }
                    let inlineByMessage = Dictionary(
                        grouping: attRecords.filter {
                            $0.contentId != nil && $0.dataBase64 != nil
                                && ($0.mime ?? "").hasPrefix("image/")
                        },
                        by: \.messageId
                    )
                    self.messages = records.map { rec in
                        let inlines = (inlineByMessage[rec.id] ?? []).compactMap { att -> InlineAttachment? in
                            guard let cid = att.contentId, let data = att.dataBase64 else { return nil }
                            return InlineAttachment(contentId: cid, mime: att.mime ?? "image/png", dataBase64: data)
                        }
                        return MessageRow(record: rec, inlineAttachments: inlines)
                    }
                    self.subject = thread?.subject ?? "(no subject)"
                    self.messageCount = thread?.messageCount ?? records.count
                    let blobByKey = Dictionary(
                        uniqueKeysWithValues: blobRecords.map {
                            (Self.blobKey(messageId: $0.messageId, attachmentId: $0.attachmentId), AttachmentCacheInfo(record: $0))
                        }
                    )
                    self.attachments = attRecords
                        .filter { $0.contentId == nil || $0.dataBase64 == nil }
                        .map { record in
                            AttachmentInfo(
                                record: record,
                                cache: blobByKey[Self.blobKey(messageId: record.messageId, attachmentId: record.id)]
                            )
                        }
                    self.isStarred = starred
                }
            } catch {
                // Observation ended
            }
        }
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        messages = []
        subject = ""
        messageCount = 0
        attachments = []
        isStarred = false
        observedThreadId = nil
        observedAccountId = nil
    }

    #if DEBUG
    func seedSnapshotForTesting(
        messages: [MessageRow],
        subject: String,
        accountEmail: String,
        messageCount: Int? = nil,
        attachments: [AttachmentInfo] = [],
        isStarred: Bool = false
    ) {
        observationTask?.cancel()
        observationTask = nil
        observedThreadId = nil
        observedAccountId = nil
        self.messages = messages
        self.subject = subject
        self.accountEmail = accountEmail
        self.messageCount = messageCount ?? messages.count
        self.attachments = attachments
        self.isStarred = isStarred
    }
    #endif

    private static func blobKey(messageId: String, attachmentId: String) -> String {
        "\(messageId)\u{1F}\(attachmentId)"
    }
}
