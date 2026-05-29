import Foundation
import GRDB
import MailDomain
import MailProviders
import Persistence

public struct GraphSyncConfiguration: Sendable, Equatable {
    public var isEnabled: Bool
    public var selectedFolderIds: [String]
    public var pageSize: Int?

    public init(
        isEnabled: Bool = false,
        selectedFolderIds: [String] = ["inbox", "sentitems", "archive", "deleteditems"],
        pageSize: Int? = 50
    ) {
        self.isEnabled = isEnabled
        self.selectedFolderIds = selectedFolderIds
        self.pageSize = pageSize
    }
}

public enum GraphSyncError: Error, Sendable, Equatable {
    case disabled
    case invalidCheckpointURL(accountId: String, folderId: String)
    case missingDeltaLink(folderId: String)
}

extension GraphSyncError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Microsoft Graph sync is disabled by feature flag."
        case .invalidCheckpointURL(_, let folderId):
            return "Microsoft Graph sync checkpoint for folder \(folderId) is not a valid URL."
        case .missingDeltaLink(let folderId):
            return "Microsoft Graph delta sync for folder \(folderId) completed without a delta link."
        }
    }
}

public actor GraphMailSyncEngine {
    public let accountId: String
    private let api: any GraphAPI
    private let db: AppDatabase
    private let configuration: GraphSyncConfiguration
    private var currentState: SyncState = .idle
    private var continuations: [UUID: AsyncStream<SyncEvent>.Continuation] = [:]
    private var retryTask: Task<Void, Never>?

    public init(
        accountId: String,
        api: any GraphAPI,
        db: AppDatabase,
        configuration: GraphSyncConfiguration = GraphSyncConfiguration()
    ) {
        self.accountId = accountId
        self.api = api
        self.db = db
        self.configuration = configuration
    }

    deinit {
        retryTask?.cancel()
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    public func makeEventStream() -> AsyncStream<SyncEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SyncEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removeContinuation(id)
            }
        }
        continuations[id] = continuation
        return stream
    }

    public func bootstrap() async {
        guard configuration.isEnabled else {
            broadcast(.error(.bootstrapFailed(GraphSyncError.disabled)))
            transition(to: .degraded)
            return
        }
        transition(to: .bootstrapping)
        await runGraphSync(isBootstrap: true)
    }

    public func refresh() async {
        guard configuration.isEnabled else {
            broadcast(.error(.incrementalFailed(GraphSyncError.disabled)))
            transition(to: .degraded)
            return
        }
        guard currentState == .live || currentState == .idle else { return }
        await runGraphSync(isBootstrap: false)
    }

    public func stop() {
        retryTask?.cancel()
        retryTask = nil
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    public var state: SyncState { currentState }

    private func runGraphSync(isBootstrap: Bool) async {
        do {
            try await GraphFolderSync.run(
                accountId: accountId,
                api: api,
                db: db,
                configuration: configuration,
                onProgress: { [weak self] progress in
                    await self?.broadcast(.progress(progress))
                },
                onThreadUpserted: { [weak self] threadId in
                    await self?.broadcast(.threadUpserted(threadId))
                }
            )
            transition(to: .live)
        } catch let error as GraphAPIError {
            handleGraphAPIError(error, isBootstrap: isBootstrap)
        } catch {
            broadcast(.error(isBootstrap ? .bootstrapFailed(error) : .incrementalFailed(error)))
            transition(to: .degraded)
        }
    }

    private func handleGraphAPIError(_ error: GraphAPIError, isBootstrap: Bool) {
        if case .rateLimited(let retryAfter) = error {
            handleRateLimited(retryAfter: retryAfter ?? 60) { engine in
                if isBootstrap {
                    await engine.bootstrap()
                } else {
                    await engine.refresh()
                }
            }
            return
        }
        broadcast(.error(isBootstrap ? .bootstrapFailed(error) : .incrementalFailed(error)))
        transition(to: .degraded)
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcast(_ event: SyncEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func transition(to newState: SyncState) {
        currentState = newState
        broadcast(.state(newState))
    }

    private func handleRateLimited(
        retryAfter: TimeInterval,
        resumeWith operation: @Sendable @escaping (isolated GraphMailSyncEngine) async -> Void
    ) {
        let capped = min(retryAfter, 300)
        broadcast(.error(.rateLimited(retryAfter: capped)))
        transition(to: .paused)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(capped))
            guard !Task.isCancelled, let self else { return }
            await operation(self)
        }
    }
}

enum GraphFolderSync {
    static func run(
        accountId: String,
        api: any GraphAPI,
        db: AppDatabase,
        configuration: GraphSyncConfiguration,
        onProgress: @Sendable (Double) async -> Void,
        onThreadUpserted: @Sendable (String) async -> Void
    ) async throws {
        let folders = try await api.listFolders().value
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        try await upsertFolders(folders, accountId: accountId, db: db)

        let selectedFolderIds = configuration.selectedFolderIds.isEmpty
            ? folders.map(\.id)
            : configuration.selectedFolderIds
        guard !selectedFolderIds.isEmpty else {
            await onProgress(1.0)
            return
        }

        for (index, folderId) in selectedFolderIds.enumerated() {
            try await syncFolder(
                folderId: folderId,
                accountId: accountId,
                api: api,
                db: db,
                foldersById: foldersById,
                pageSize: configuration.pageSize,
                onThreadUpserted: onThreadUpserted
            )
            await onProgress(Double(index + 1) / Double(selectedFolderIds.count))
        }
    }

    private static func syncFolder(
        folderId: String,
        accountId: String,
        api: any GraphAPI,
        db: AppDatabase,
        foldersById: [String: GraphDTO.MailFolder],
        pageSize: Int?,
        onThreadUpserted: @Sendable (String) async -> Void
    ) async throws {
        var deltaURL = try await checkpointURL(accountId: accountId, folderId: folderId, db: db)
        var finalDeltaLink: String?

        repeat {
            let response = try await api.folderMessageDelta(
                folderId: folderId,
                deltaURL: deltaURL,
                pageSize: pageSize
            )

            for message in response.value {
                let change = GraphMapper.mapMessageChange(
                    messageWithFallbackParentFolder(message, folderId: folderId),
                    accountId: accountId,
                    foldersById: foldersById
                )
                switch change {
                case .upsert(let mapped):
                    try await upsertMessage(mapped, source: message, accountId: accountId, db: db)
                    await onThreadUpserted(mapped.message.threadId)
                case .removed(let removed):
                    let threadId = try await removeMessage(removed, accountId: accountId, db: db)
                    if let threadId {
                        await onThreadUpserted(threadId)
                    }
                case nil:
                    continue
                }
            }

            if let nextLink = response.nextLink {
                guard let nextURL = URL(string: nextLink) else {
                    throw GraphSyncError.invalidCheckpointURL(accountId: accountId, folderId: folderId)
                }
                deltaURL = nextURL
            } else {
                deltaURL = nil
            }
            finalDeltaLink = response.deltaLink
        } while deltaURL != nil

        guard let finalDeltaLink else {
            throw GraphSyncError.missingDeltaLink(folderId: folderId)
        }
        try await saveCheckpoint(
            accountId: accountId,
            folderId: folderId,
            deltaURL: finalDeltaLink,
            db: db
        )
    }

    @DatabaseActor
    private static func checkpointURL(accountId: String, folderId: String, db: AppDatabase) throws -> URL? {
        let raw = try db.read { dbConn in
            try GraphDeltaCheckpointRecord.fetchOne(
                dbConn,
                key: ["account_id": accountId, "folder_id": folderId]
            )?.deltaURL
        }
        guard let raw else { return nil }
        guard let url = URL(string: raw) else {
            throw GraphSyncError.invalidCheckpointURL(accountId: accountId, folderId: folderId)
        }
        return url
    }

    @DatabaseActor
    private static func upsertFolders(_ folders: [GraphDTO.MailFolder], accountId: String, db: AppDatabase) throws {
        try db.write { dbConn in
            for folder in folders {
                let mapped = GraphMapper.mapFolder(folder, accountId: accountId)
                let label = labelRecord(for: mapped.mailbox, accountId: accountId, fallbackName: mapped.displayName)
                try label.save(dbConn, onConflict: .replace)
            }
        }
    }

    @DatabaseActor
    private static func upsertMessage(
        _ mapped: GraphMappedMessage,
        source: GraphDTO.Message,
        accountId: String,
        db: AppDatabase
    ) throws {
        let message = mapped.message
        try db.write { dbConn in
            try upsertThreadForMessage(message, subject: source.subject, db: dbConn)
            try upsertMessageRecord(makeMessageRecord(from: message, accountId: accountId), db: dbConn)

            try AttachmentRecord
                .filter(Column("account_id") == accountId && Column("message_id") == message.id)
                .deleteAll(dbConn)
            for attachment in message.attachments {
                try makeAttachmentRecord(from: attachment, messageId: message.id, accountId: accountId)
                    .insert(dbConn)
            }

            try ThreadLabelRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == message.threadId)
                .deleteAll(dbConn)
            let mailboxes = mailboxes(for: mapped)
            for mailbox in mailboxes {
                let label = labelRecord(for: mailbox, accountId: accountId, fallbackName: nil)
                try label.save(dbConn, onConflict: .replace)
                try ThreadLabelRecord(accountId: accountId, threadId: message.threadId, labelId: label.id)
                    .insert(dbConn, onConflict: .ignore)
            }

            try refreshThreadAggregate(threadId: message.threadId, accountId: accountId, subject: source.subject, db: dbConn)
        }
    }

    @DatabaseActor
    private static func removeMessage(
        _ removed: GraphRemovedMessage,
        accountId: String,
        db: AppDatabase
    ) throws -> String? {
        try db.write { dbConn in
            let existing = try MessageRecord.fetchOne(dbConn, key: ["account_id": accountId, "id": removed.id])
            try MessageRecord.deleteOne(dbConn, key: ["account_id": accountId, "id": removed.id])
            guard let threadId = existing?.threadId else { return nil }

            let remaining = try MessageRecord
                .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                .fetchCount(dbConn)
            if remaining == 0 {
                try ThreadLabelRecord
                    .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
                    .deleteAll(dbConn)
                try ThreadRecord.deleteOne(dbConn, key: ["account_id": accountId, "id": threadId])
            } else {
                try refreshThreadAggregate(threadId: threadId, accountId: accountId, subject: nil, db: dbConn)
            }
            return threadId
        }
    }

    @DatabaseActor
    private static func saveCheckpoint(accountId: String, folderId: String, deltaURL: String, db: AppDatabase) throws {
        try db.write { dbConn in
            try GraphDeltaCheckpointRecord(
                accountId: accountId,
                folderId: folderId,
                deltaURL: deltaURL,
                updatedAt: Int(Date().timeIntervalSince1970)
            ).save(dbConn, onConflict: .replace)
        }
    }

    private static func messageWithFallbackParentFolder(_ message: GraphDTO.Message, folderId: String) -> GraphDTO.Message {
        guard message.parentFolderId == nil else { return message }
        return GraphDTO.Message(
            id: message.id,
            changeKey: message.changeKey,
            internetMessageId: message.internetMessageId,
            conversationId: message.conversationId,
            parentFolderId: folderId,
            subject: message.subject,
            bodyPreview: message.bodyPreview,
            body: message.body,
            from: message.from,
            sender: message.sender,
            toRecipients: message.toRecipients,
            ccRecipients: message.ccRecipients,
            bccRecipients: message.bccRecipients,
            replyTo: message.replyTo,
            receivedDateTime: message.receivedDateTime,
            sentDateTime: message.sentDateTime,
            isRead: message.isRead,
            isDraft: message.isDraft,
            hasAttachments: message.hasAttachments,
            attachments: message.attachments,
            categories: message.categories,
            flag: message.flag,
            deletedReason: message.deletedReason,
            odataType: message.odataType,
            odataRemoved: message.odataRemoved
        )
    }

    private static func upsertMessageRecord(_ record: MessageRecord, db: Database) throws {
        if try MessageRecord.fetchOne(db, key: ["account_id": record.accountId, "id": record.id]) != nil {
            try record.update(db)
        } else {
            try record.insert(db)
        }
    }

    private static func upsertThreadForMessage(_ message: Message, subject: String?, db: Database) throws {
        if try ThreadRecord.fetchOne(db, key: ["account_id": message.accountId, "id": message.threadId]) == nil {
            try ThreadRecord(
                id: message.threadId,
                accountId: message.accountId,
                subject: subject,
                snippet: message.snippet,
                lastMessageAt: Int(message.sentAt.timeIntervalSince1970),
                messageCount: 0,
                hasUnread: message.isUnread ? 1 : 0
            ).insert(db)
        }
    }

    private static func refreshThreadAggregate(
        threadId: String,
        accountId: String,
        subject: String?,
        db: Database
    ) throws {
        let messages = try MessageRecord
            .filter(Column("account_id") == accountId && Column("thread_id") == threadId)
            .order(Column("sent_at").desc)
            .fetchAll(db)
        guard let latest = messages.first else { return }
        let unread = messages.contains { ($0.flags & MessageRecord.read) == 0 }
        let existing = try ThreadRecord.fetchOne(db, key: ["account_id": accountId, "id": threadId])
        try ThreadRecord(
            id: threadId,
            accountId: accountId,
            subject: subject ?? existing?.subject,
            snippet: latest.snippet,
            lastMessageAt: latest.sentAt,
            messageCount: messages.count,
            hasUnread: unread ? 1 : 0
        ).save(db, onConflict: .replace)
    }

    private static func mailboxes(for mapped: GraphMappedMessage) -> [CanonicalMailbox] {
        var mailboxes: [CanonicalMailbox] = []
        if let mailbox = mapped.mailbox {
            mailboxes.append(mailbox)
        }
        mailboxes.append(contentsOf: mapped.categoryMailboxes)
        return mailboxes
    }

    private static func labelRecord(
        for mailbox: CanonicalMailbox,
        accountId: String,
        fallbackName: String?
    ) -> LabelRecord {
        let identity = labelIdentity(for: mailbox, fallbackName: fallbackName)
        return LabelRecord(id: identity.id, accountId: accountId, name: identity.name, type: identity.type)
    }

    private static func labelIdentity(
        for mailbox: CanonicalMailbox,
        fallbackName: String?
    ) -> (id: String, name: String, type: LabelType) {
        switch mailbox {
        case .inbox:
            return ("INBOX", "Inbox", .system)
        case .sent:
            return ("SENT", "Sent", .system)
        case .drafts:
            return ("DRAFT", "Drafts", .system)
        case .trash:
            return ("TRASH", "Trash", .system)
        case .spam:
            return ("SPAM", "Spam", .system)
        case .archive:
            return ("ARCHIVE", "Archive", .system)
        case .starred, .flagged:
            return ("STARRED", "Starred", .system)
        case .userDefined(let id, let name, let kind):
            return (id, name ?? fallbackName ?? id, kind == .category ? .category : .user)
        }
    }
}
