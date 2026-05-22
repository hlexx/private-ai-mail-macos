import Foundation
import GRDB
import MailProviders
import Persistence
import os

public enum MailMutationError: Error, Sendable, Equatable {
    case missingCredential(accountId: String)
    case providerRejected(reason: ProviderRejection)
    case rateLimited(retryAfter: TimeInterval?)
    case offline
    case degradedSync
    case providerFailure

    public enum ProviderRejection: Sendable, Equatable {
        case unauthorized
        case insufficientScope
        case forbidden
        case statusCode(Int)
    }

    static func provider(_ error: any Error) -> MailMutationError {
        if let mutationError = error as? MailMutationError {
            return mutationError
        }
        guard let gmailError = error as? GmailAPIError else {
            return .providerFailure
        }
        switch gmailError {
        case .unauthorized:
            return .providerRejected(reason: .unauthorized)
        case .insufficientScope:
            return .providerRejected(reason: .insufficientScope)
        case .rateLimited(let retryAfter):
            return .rateLimited(retryAfter: retryAfter)
        case .networkError:
            return .offline
        case .serverError(let statusCode) where statusCode == 403:
            return .providerRejected(reason: .forbidden)
        case .serverError(let statusCode) where statusCode >= 500:
            return .degradedSync
        case .serverError(let statusCode):
            return .providerRejected(reason: .statusCode(statusCode))
        case .exhaustedRetries, .decodingError, .invalidResponse:
            return .degradedSync
        }
    }
}

extension MailMutationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Missing Gmail credentials. Reconnect the account and try again."
        case .providerRejected(let reason):
            switch reason {
            case .unauthorized:
                return "Gmail rejected the request because the account is no longer authorized."
            case .insufficientScope:
                return "Gmail rejected the request because the account is missing the required permission."
            case .forbidden:
                return "Gmail rejected the request for this account."
            case .statusCode(let statusCode):
                return "Gmail rejected the request (HTTP \(statusCode))."
            }
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Gmail rate limit hit. Try again in \(Int(retryAfter))s."
            }
            return "Gmail rate limit hit. Try again later."
        case .offline:
            return "Network is offline or unreachable. The local mailbox was not changed."
        case .degradedSync:
            return "Gmail sync is degraded. The local mailbox was restored."
        case .providerFailure:
            return "Gmail action failed. The local mailbox was restored."
        }
    }
}

public actor MailMutator {
    private let db: AppDatabase
    private let apiFactory: @Sendable (String) throws -> any GmailAPI
    private let logger = Logger(subsystem: "com.privateaimail.mailsync", category: "MailMutation")

    public init(db: AppDatabase, apiFactory: @Sendable @escaping (String) throws -> any GmailAPI) {
        self.db = db
        self.apiFactory = apiFactory
    }

    public func archive(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            action: "archive",
            threadId: threadId,
            accountId: accountId,
            addLabelIds: [],
            removeLabelIds: ["INBOX"]
        )
    }

    public func unarchive(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            action: "unarchive",
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["INBOX"],
            removeLabelIds: []
        )
    }

    public func star(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            action: "star",
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["STARRED"],
            removeLabelIds: []
        )
    }

    public func unstar(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            action: "unstar",
            threadId: threadId,
            accountId: accountId,
            addLabelIds: [],
            removeLabelIds: ["STARRED"]
        )
    }

    public func markRead(_ threadId: String, accountId: String, read: Bool) async throws {
        let action = read ? "mark_read" : "mark_unread"
        let api = try resolveAPI(accountId: accountId, threadId: threadId, action: action)
        let readFlag = MessageRecord.read
        let snapshot = try await readStateSnapshot(
            accountId: accountId,
            threadId: threadId
        )

        logStart(action: action, accountId: accountId, threadId: threadId)
        try await db.dbQueue.write { dbConn in
            if read {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD").delete(dbConn)
            } else {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD")
                    .insert(dbConn, onConflict: .ignore)
            }
            if read {
                try dbConn.execute(
                    sql: "UPDATE message SET flags = flags | ? WHERE account_id = ? AND thread_id = ?",
                    arguments: [readFlag, accountId, threadId]
                )
            } else {
                try dbConn.execute(
                    sql: "UPDATE message SET flags = flags & ~? WHERE account_id = ? AND thread_id = ?",
                    arguments: [readFlag, accountId, threadId]
                )
            }
            try dbConn.execute(
                sql: "UPDATE thread SET has_unread = ? WHERE account_id = ? AND id = ?",
                arguments: [read ? 0 : 1, accountId, threadId]
            )
        }

        do {
            _ = try await api.modifyThread(
                id: threadId,
                addLabelIds: read ? [] : ["UNREAD"],
                removeLabelIds: read ? ["UNREAD"] : []
            )
            logSuccess(action: action, accountId: accountId, threadId: threadId)
        } catch {
            try? await restoreReadState(snapshot, accountId: accountId, threadId: threadId)
            let mutationError = MailMutationError.provider(error)
            logFailure(action: action, accountId: accountId, threadId: threadId, error: mutationError)
            throw mutationError
        }
    }

    public func trash(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            action: "trash",
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["TRASH"],
            removeLabelIds: ["INBOX"]
        )
    }

    public func untrash(_ threadId: String, accountId: String) async throws {
        try await mutateLabels(
            action: "untrash",
            threadId: threadId,
            accountId: accountId,
            addLabelIds: ["INBOX"],
            removeLabelIds: ["TRASH"]
        )
    }

    // MARK: - Core mutation

    private func mutateLabels(
        action: String,
        threadId: String,
        accountId: String,
        addLabelIds: [String],
        removeLabelIds: [String]
    ) async throws {
        let api = try resolveAPI(accountId: accountId, threadId: threadId, action: action)
        let snapshot = try await labelSnapshot(
            accountId: accountId,
            threadId: threadId,
            labelIds: Array(Set(addLabelIds + removeLabelIds))
        )

        logStart(action: action, accountId: accountId, threadId: threadId)
        try await db.dbQueue.write { dbConn in
            for labelId in removeLabelIds {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId).delete(dbConn)
            }
            for labelId in addLabelIds {
                let record = ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId)
                try record.insert(dbConn, onConflict: .ignore)
            }
        }

        do {
            _ = try await api.modifyThread(
                id: threadId,
                addLabelIds: addLabelIds,
                removeLabelIds: removeLabelIds
            )
            logSuccess(action: action, accountId: accountId, threadId: threadId)
        } catch {
            try? await restoreLabels(
                snapshot,
                accountId: accountId,
                threadId: threadId
            )
            let mutationError = MailMutationError.provider(error)
            logFailure(action: action, accountId: accountId, threadId: threadId, error: mutationError)
            throw mutationError
        }
    }

    private func resolveAPI(accountId: String, threadId: String, action: String) throws -> any GmailAPI {
        do {
            return try apiFactory(accountId)
        } catch let error as MailMutationError {
            logFailure(action: action, accountId: accountId, threadId: threadId, error: error)
            throw error
        } catch {
            let mutationError = MailMutationError.missingCredential(accountId: accountId)
            logFailure(action: action, accountId: accountId, threadId: threadId, error: mutationError)
            throw mutationError
        }
    }

    private struct LabelStateSnapshot: Sendable {
        let trackedLabels: Set<String>
        let activeLabels: Set<String>
    }

    private func labelSnapshot(
        accountId: String,
        threadId: String,
        labelIds: [String]
    ) async throws -> LabelStateSnapshot {
        let trackedLabels = Set(labelIds)
        guard !labelIds.isEmpty else {
            return LabelStateSnapshot(trackedLabels: [], activeLabels: [])
        }
        return try await db.dbQueue.read { dbConn in
            let rows = try ThreadLabelRecord
                .filter(Column("account_id") == accountId)
                .filter(Column("thread_id") == threadId)
                .fetchAll(dbConn)
            let activeLabels = Set(rows.map(\.labelId)).intersection(trackedLabels)
            return LabelStateSnapshot(trackedLabels: trackedLabels, activeLabels: activeLabels)
        }
    }

    private func restoreLabels(
        _ snapshot: LabelStateSnapshot,
        accountId: String,
        threadId: String
    ) async throws {
        try await db.dbQueue.write { dbConn in
            for labelId in snapshot.trackedLabels {
                if snapshot.activeLabels.contains(labelId) {
                    let record = ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId)
                    try record.insert(dbConn, onConflict: .ignore)
                } else {
                    try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: labelId).delete(dbConn)
                }
            }
        }
    }

    private struct ReadStateSnapshot: Sendable {
        let hasUnread: Int?
        let hasUnreadLabel: Bool
        let messageFlags: [String: Int]
    }

    private func readStateSnapshot(accountId: String, threadId: String) async throws -> ReadStateSnapshot {
        try await db.dbQueue.read { dbConn in
            let hasUnread = try Int.fetchOne(
                dbConn,
                sql: "SELECT has_unread FROM thread WHERE account_id = ? AND id = ?",
                arguments: [accountId, threadId]
            )
            let unreadLabel = try ThreadLabelRecord
                .filter(Column("account_id") == accountId)
                .filter(Column("thread_id") == threadId)
                .filter(Column("label_id") == "UNREAD")
                .fetchOne(dbConn) != nil
            let rows = try Row.fetchAll(
                dbConn,
                sql: "SELECT id, flags FROM message WHERE account_id = ? AND thread_id = ?",
                arguments: [accountId, threadId]
            )
            let messageFlags = Dictionary(uniqueKeysWithValues: rows.map { row in
                let id: String = row["id"]
                let flags: Int = row["flags"]
                return (id, flags)
            })
            return ReadStateSnapshot(
                hasUnread: hasUnread,
                hasUnreadLabel: unreadLabel,
                messageFlags: messageFlags
            )
        }
    }

    private func restoreReadState(
        _ snapshot: ReadStateSnapshot,
        accountId: String,
        threadId: String
    ) async throws {
        try await db.dbQueue.write { dbConn in
            if snapshot.hasUnreadLabel {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD")
                    .insert(dbConn, onConflict: .ignore)
            } else {
                try ThreadLabelRecord(accountId: accountId, threadId: threadId, labelId: "UNREAD").delete(dbConn)
            }
            if let hasUnread = snapshot.hasUnread {
                try dbConn.execute(
                    sql: "UPDATE thread SET has_unread = ? WHERE account_id = ? AND id = ?",
                    arguments: [hasUnread, accountId, threadId]
                )
            }
            for (messageId, flags) in snapshot.messageFlags {
                try dbConn.execute(
                    sql: "UPDATE message SET flags = ? WHERE account_id = ? AND thread_id = ? AND id = ?",
                    arguments: [flags, accountId, threadId, messageId]
                )
            }
        }
    }

    private func logStart(action: String, accountId: String, threadId: String) {
        logger.info(
            "mail mutation start action=\(action, privacy: .public) account_id=\(accountId, privacy: .public) thread_id=\(threadId, privacy: .public)"
        )
    }

    private func logSuccess(action: String, accountId: String, threadId: String) {
        logger.info(
            "mail mutation success action=\(action, privacy: .public) account_id=\(accountId, privacy: .public) thread_id=\(threadId, privacy: .public)"
        )
    }

    private func logFailure(action: String, accountId: String, threadId: String, error: MailMutationError) {
        logger.error(
            "mail mutation failure action=\(action, privacy: .public) account_id=\(accountId, privacy: .public) thread_id=\(threadId, privacy: .public) reason=\(String(describing: error), privacy: .public)"
        )
    }
}
