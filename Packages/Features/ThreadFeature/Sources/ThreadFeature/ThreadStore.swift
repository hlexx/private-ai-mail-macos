import Foundation
import GRDB
import Observation
import Persistence

public struct MessageRow: Identifiable, Sendable {
    public let id: String
    public let threadId: String
    public let messageIdHeader: String?
    public let fromAddr: String
    public let toAddr: String?
    public let sentAt: Date
    public let snippet: String
    public let bodyText: String
    public let flags: Int

    public var isSentByMe: Bool {
        (flags & MessageRecord.sentByMe) != 0
    }

    public init(record: MessageRecord) {
        self.id = record.id
        self.threadId = record.threadId
        self.messageIdHeader = record.messageIdHeader
        self.fromAddr = record.fromAddr ?? "(unknown)"
        self.toAddr = record.toAddr
        self.sentAt = Date(timeIntervalSince1970: TimeInterval(record.sentAt))
        self.snippet = record.snippet ?? ""
        self.bodyText = record.bodyText ?? record.snippet ?? ""
        self.flags = record.flags
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
    public let filename: String
    public let sizeBytes: Int?
    public let mime: String?

    public init(record: AttachmentRecord) {
        self.id = record.id
        self.filename = record.filename ?? "attachment"
        self.sizeBytes = record.sizeBytes
        self.mime = record.mime
    }

    public init(id: String, filename: String, sizeBytes: Int?, mime: String?) {
        self.id = id
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.mime = mime
    }

    public var formattedSize: String {
        guard let bytes = sizeBytes else { return "" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

@Observable
@MainActor
public final class ThreadStore {
    public private(set) var messages: [MessageRow] = []
    public private(set) var subject: String = ""
    public private(set) var messageCount: Int = 0
    public private(set) var attachments: [AttachmentInfo] = []
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
        observationTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db in
                let thread = try ThreadRecord
                    .filter(Column("id") == threadId && Column("account_id") == accountId)
                    .fetchOne(db)

                let messages = try MessageRecord
                    .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                    .order(Column("sent_at").asc)
                    .fetchAll(db)

                let messageIds = messages.map(\.id)
                let attachments: [AttachmentRecord]
                if messageIds.isEmpty {
                    attachments = []
                } else {
                    attachments = try AttachmentRecord
                        .filter(messageIds.contains(Column("message_id")))
                        .fetchAll(db)
                }

                return (thread, messages, attachments)
            }
            do {
                for try await (thread, records, attRecords) in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled, let self else { return }
                    self.messages = records.map(MessageRow.init)
                    self.subject = thread?.subject ?? "(no subject)"
                    self.messageCount = thread?.messageCount ?? records.count
                    self.attachments = attRecords.map(AttachmentInfo.init)
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
    }
}
