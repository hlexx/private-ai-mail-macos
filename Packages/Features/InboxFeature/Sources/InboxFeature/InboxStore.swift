import Foundation
import GRDB
import Observation
import Persistence

public enum ThreadFilter: String, CaseIterable, Sendable {
    case all
    case needsReply = "reply"
    case hasDeadline = "due"
    case hasAttachment = "att"
    case aiHandled = "ai"

    public var label: String {
        switch self {
        case .all: return String(localized: "filter.all", defaultValue: "All")
        case .needsReply: return String(localized: "filter.needsReply", defaultValue: "Needs reply")
        case .hasDeadline: return String(localized: "filter.hasDeadline", defaultValue: "Has deadline")
        case .hasAttachment: return String(localized: "filter.attachments", defaultValue: "Attachments")
        case .aiHandled: return String(localized: "filter.aiHandled", defaultValue: "AI handled")
        }
    }
}

public struct ThreadRow: Identifiable, Sendable, Hashable {
    public let id: String
    public let accountId: String
    public let subject: String
    public let snippet: String
    public let lastMessageAt: Date
    public let messageCount: Int
    public let hasUnread: Bool
    public let senderName: String
    public let senderAddr: String
    public let attachmentCount: Int

    public init(record: ThreadRecord, latestFromAddr: String? = nil, attachmentCount: Int = 0) {
        self.id = record.id
        self.accountId = record.accountId
        self.subject = record.subject ?? "(no subject)"
        self.snippet = record.snippet ?? ""
        self.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(record.lastMessageAt))
        self.messageCount = record.messageCount
        self.hasUnread = record.hasUnread != 0
        self.attachmentCount = attachmentCount

        let addr = latestFromAddr ?? ""
        self.senderAddr = addr
        self.senderName = Self.extractName(from: addr)
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

@Observable
@MainActor
public final class InboxStore {
    public private(set) var threads: [ThreadRow] = []
    public var selectedThreadID: String?
    public var filter: ThreadFilter = .all {
        didSet { if oldValue != filter { startObserving() } }
    }

    public var selection: SidebarSelection = .default {
        didSet { if oldValue != selection { startObserving() } }
    }

    public internal(set) var folderCounts: [FolderID: Int] = [:]

    public var filteredThreads: [ThreadRow] {
        threads
    }

    public var needsReplyCount: Int {
        folderCounts[.needsReply] ?? 0
    }

    let db: AppDatabase
    var observationTask: Task<Void, Never>?
    var countsTask: Task<Void, Never>?

    public init(db: AppDatabase) {
        self.db = db
    }

    public func setSelection(_ sel: SidebarSelection) {
        selection = sel
    }

    public func startObserving() {
        observationTask?.cancel()
        let currentSelection = selection
        let currentFilter = filter
        do {
            let records = try db.read { db in
                try Self.queryThreads(db: db, selection: currentSelection, filter: currentFilter)
            }
            threads = Self.threadRows(from: records)
        } catch {
            threads = []
        }
        observationTask = Task { [weak self, db] in
            let observation = ValueObservation.tracking { db in
                try Self.queryThreads(db: db, selection: currentSelection, filter: currentFilter)
            }
            do {
                for try await records in observation.values(in: db.dbQueue) {
                    guard !Task.isCancelled, let self else { return }
                    self.threads = Self.threadRows(from: records)
                }
            } catch {
                // Observation ended
            }
        }
        startCountsObservation()
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        countsTask?.cancel()
        countsTask = nil
    }

    private nonisolated static func threadRows(
        from records: [(ThreadRecord, String?, Int)]
    ) -> [ThreadRow] {
        records.map { thread, fromAddr, attCount in
            ThreadRow(record: thread, latestFromAddr: fromAddr, attachmentCount: attCount)
        }
    }

}
