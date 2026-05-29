import GRDB
import Persistence
import Testing

@Suite("Graph delta checkpoint persistence")
struct GraphDeltaCheckpointMigrationTests {
    @Test func checkpointRoundTripIsScopedByAccountAndFolder() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try AccountRecord(id: "outlook-a", provider: "outlook", email: "a@example.com", createdAt: 1).insert(dbConn)
                try AccountRecord(id: "outlook-b", provider: "outlook", email: "b@example.com", createdAt: 2).insert(dbConn)
                try GraphDeltaCheckpointRecord(
                    accountId: "outlook-a",
                    folderId: "inbox",
                    deltaURL: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=a",
                    updatedAt: 10
                ).insert(dbConn)
                try GraphDeltaCheckpointRecord(
                    accountId: "outlook-b",
                    folderId: "inbox",
                    deltaURL: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=b",
                    updatedAt: 20
                ).insert(dbConn)
            }
        }

        let checkpoints = try db.read { dbConn in
            try GraphDeltaCheckpointRecord.order(Column("account_id")).fetchAll(dbConn)
        }
        #expect(checkpoints.map(\.accountId) == ["outlook-a", "outlook-b"])
        #expect(checkpoints[0].deltaURL.contains("deltatoken=a"))
        #expect(checkpoints[1].deltaURL.contains("deltatoken=b"))
    }

    @Test func checkpointsCascadeWhenAccountIsRemoved() async throws {
        let db = try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try AccountRecord(id: "outlook-1", provider: "outlook", email: "o@example.com", createdAt: 1).insert(dbConn)
                try GraphDeltaCheckpointRecord(
                    accountId: "outlook-1",
                    folderId: "inbox",
                    deltaURL: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=opaque",
                    updatedAt: 10
                ).insert(dbConn)
                _ = try AccountRecord.deleteOne(dbConn, key: "outlook-1")
            }
        }

        let count = try db.read { dbConn in
            try GraphDeltaCheckpointRecord.fetchCount(dbConn)
        }
        #expect(count == 0)
    }
}
