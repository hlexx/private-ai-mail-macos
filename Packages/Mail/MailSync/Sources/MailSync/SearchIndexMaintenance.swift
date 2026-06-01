import GRDB
import Persistence

enum SearchIndexMaintenance {
    static func upsertMessage(accountId: String, messageId: String, db: Database) throws {
        try LocalSearchIndexPersistence.upsertMessage(accountId: accountId, messageId: messageId, in: db)
    }

    static func upsertMessages(accountId: String, messageIds: some Sequence<String>, db: Database) throws {
        for messageId in messageIds {
            try upsertMessage(accountId: accountId, messageId: messageId, db: db)
        }
    }

    static func deleteMessage(accountId: String, messageId: String, db: Database) throws {
        try LocalSearchIndexPersistence.deleteMessage(accountId: accountId, messageId: messageId, in: db)
    }
}
