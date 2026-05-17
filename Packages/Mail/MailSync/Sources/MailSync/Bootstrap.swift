import Foundation
import GRDB
import MailDomain
import MailProviders
import Persistence

enum Bootstrap {
    static func run(
        accountId: String,
        api: any GmailAPI,
        db: AppDatabase,
        onProgress: @Sendable (Double) async -> Void,
        onThreadUpserted: @Sendable (String) async -> Void
    ) async throws {
        // Step 0: Fetch and upsert labels
        let labels = try await api.listLabels()
        try await upsertLabels(labels, accountId: accountId, db: db)
        await onProgress(0.02)

        // Step 1: Page through messages.list to collect unique thread IDs
        var threadIds = Set<String>()
        var pageToken: String?
        let query = "newer_than:30d"

        repeat {
            let list = try await api.listMessages(query: query, pageToken: pageToken, maxResults: 500)
            for ref in list.messages ?? [] {
                threadIds.insert(ref.threadId)
            }
            pageToken = list.nextPageToken
        } while pageToken != nil

        let totalThreads = threadIds.count
        guard totalThreads > 0 else {
            try await finalizeSyncState(accountId: accountId, historyId: nil, db: db)
            await onProgress(1.0)
            return
        }

        // Step 2: Fetch threads in batches with concurrency limit
        let sortedIds = Array(threadIds)
        let batchSize = 50
        var processedCount = 0
        var latestHistoryId: String?

        for batchStart in stride(from: 0, to: sortedIds.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, sortedIds.count)
            let batch = Array(sortedIds[batchStart..<batchEnd])

            let threads = try await fetchThreadsConcurrently(
                ids: batch,
                api: api,
                accountId: accountId,
                maxConcurrent: 5
            )

            // Upsert batch to DB
            try await upsertThreads(threads, accountId: accountId, db: db)

            for thread in threads {
                if let hid = thread.historyId, let current = latestHistoryId {
                    if (UInt64(hid) ?? 0) > (UInt64(current) ?? 0) { latestHistoryId = hid }
                } else if let hid = thread.historyId {
                    latestHistoryId = hid
                }
                await onThreadUpserted(thread.id)
            }

            processedCount += batch.count
            await onProgress(Double(processedCount) / Double(totalThreads))
        }

        try await finalizeSyncState(accountId: accountId, historyId: latestHistoryId, db: db)
    }

    private static func fetchThreadsConcurrently(
        ids: [String],
        api: any GmailAPI,
        accountId: String,
        maxConcurrent: Int
    ) async throws -> [GmailDTO.Thread] {
        try await withThrowingTaskGroup(of: GmailDTO.Thread.self) { group in
            var results: [GmailDTO.Thread] = []
            var index = 0

            for _ in 0..<min(maxConcurrent, ids.count) {
                let id = ids[index]
                index += 1
                group.addTask {
                    try await api.getThread(id: id, format: .full)
                }
            }

            for try await thread in group {
                results.append(thread)
                if index < ids.count {
                    let id = ids[index]
                    index += 1
                    group.addTask {
                        try await api.getThread(id: id, format: .full)
                    }
                }
            }

            return results
        }
    }

    @DatabaseActor
    private static func upsertLabels(
        _ labels: [GmailDTO.Label],
        accountId: String,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            for label in labels {
                let labelType: LabelType
                if label.name.hasPrefix("CATEGORY_") {
                    labelType = .category
                } else if label.type == "system" {
                    labelType = .system
                } else {
                    labelType = .user
                }
                let record = LabelRecord(
                    id: label.id,
                    accountId: accountId,
                    name: label.name,
                    type: labelType,
                    color: label.color?.backgroundColor,
                    messagesUnreadCount: label.messagesUnread ?? 0,
                    messagesTotalCount: label.messagesTotal ?? 0
                )
                try record.save(dbConn, onConflict: .replace)
            }
        }
    }

    @DatabaseActor
    private static func upsertThreads(
        _ dtoThreads: [GmailDTO.Thread],
        accountId: String,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            for dto in dtoThreads {
                let mapped = GmailMapper.mapThread(dto, accountId: accountId)
                try makeThreadRecord(from: mapped, accountId: accountId)
                    .save(dbConn, onConflict: .replace)

                // Collect thread-level labels (union of all message labels)
                var threadLabelIds = Set<String>()

                for dtoMsg in dto.messages ?? [] {
                    let (msg, labelIds) = GmailMapper.mapMessageWithLabels(dtoMsg, accountId: accountId)
                    try makeMessageRecord(from: msg, accountId: accountId)
                        .save(dbConn, onConflict: .replace)

                    for att in msg.attachments {
                        try makeAttachmentRecord(from: att, messageId: msg.id, accountId: accountId)
                            .save(dbConn, onConflict: .replace)
                    }

                    threadLabelIds.formUnion(labelIds)
                }

                // Replace thread_label rows for this thread
                try ThreadLabelRecord
                    .filter(Column("thread_id") == dto.id)
                    .deleteAll(dbConn)
                for labelId in threadLabelIds {
                    try ThreadLabelRecord(threadId: dto.id, labelId: labelId)
                        .save(dbConn, onConflict: .replace)
                }
            }
        }
    }

    @DatabaseActor
    private static func finalizeSyncState(
        accountId: String,
        historyId: String?,
        db: AppDatabase
    ) throws {
        try db.write { dbConn in
            var syncState = try SyncStateRecord.fetchOne(
                dbConn,
                key: ["account_id": accountId]
            ) ?? SyncStateRecord(accountId: accountId)
            if let hid = historyId {
                syncState.historyId = hid
            }
            syncState.lastBootstrapAt = Int(Date().timeIntervalSince1970)
            syncState.status = SyncState.live.rawValue
            try syncState.save(dbConn, onConflict: .replace)
        }
    }
}
