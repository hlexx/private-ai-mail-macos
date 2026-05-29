import Foundation
import GRDB
import MailProviders
@testable import MailSync
import Persistence
import Testing

@Suite("GraphMailSyncEngine", .serialized)
struct GraphMailSyncEngineTests {
    private func makeDB() async throws -> AppDatabase {
        try await DatabaseActor.shared.run {
            try AppDatabase.openInMemory()
        }
    }

    private func seedOutlookAccount(_ db: AppDatabase, id: String = "outlook-1") async throws {
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try AccountRecord(
                    id: id,
                    provider: "outlook",
                    email: "outlook@example.com",
                    createdAt: 1_700_000_000
                ).insert(dbConn)
            }
        }
    }

    @Test func initialSyncPersistsMessageLabelsAndDeltaCheckpoint() async throws {
        let db = try await makeDB()
        try await seedOutlookAccount(db)
        let api = MockGraphAPI()
        api.deltaResults["folder:inbox"] = [
            .success(GraphDTO.MessageDeltaResponse(
                value: [
                    graphMessage(
                        id: "m1",
                        conversationId: "c1",
                        parentFolderId: "inbox",
                        subject: "Hello Graph",
                        isRead: false,
                        categories: ["Client"],
                        isFlagged: true
                    )
                ],
                deltaLink: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=opaque-final"
            ))
        ]

        let engine = GraphMailSyncEngine(
            accountId: "outlook-1",
            api: api,
            db: db,
            configuration: GraphSyncConfiguration(isEnabled: true, selectedFolderIds: ["inbox"])
        )
        await engine.bootstrap()

        let messageID = "outlook:outlook-1:message:m1"
        let threadID = "outlook:outlook-1:conversation:c1"
        let snapshot = try db.read { dbConn in
            (
                try MessageRecord.fetchOne(dbConn, key: ["account_id": "outlook-1", "id": messageID]),
                try ThreadRecord.fetchOne(dbConn, key: ["account_id": "outlook-1", "id": threadID]),
                try String.fetchAll(
                    dbConn,
                    sql: """
                    SELECT label_id FROM thread_label
                    WHERE account_id = ? AND thread_id = ?
                    ORDER BY label_id
                    """,
                    arguments: ["outlook-1", threadID]
                ),
                try GraphDeltaCheckpointRecord.fetchOne(
                    dbConn,
                    key: ["account_id": "outlook-1", "folder_id": "inbox"]
                ),
                try MailSearchDocumentRecord.fetchOne(
                    dbConn,
                    sql: "SELECT * FROM mail_search_document WHERE account_id = ? AND message_id = ?",
                    arguments: ["outlook-1", messageID]
                )
            )
        }

        #expect(snapshot.0?.snippet == "Preview m1")
        #expect(snapshot.1?.subject == "Hello Graph")
        #expect(snapshot.1?.messageCount == 1)
        #expect(snapshot.1?.hasUnread == 1)
        #expect(snapshot.2 == ["Client", "INBOX", "STARRED"])
        #expect(snapshot.3?.deltaURL.contains("opaque-final") == true)
        #expect(snapshot.4?.provider == "outlook")
        #expect(snapshot.4?.canonicalMailboxes == "Client INBOX STARRED")
        #expect(snapshot.4?.hasAttachment == 1)
        #expect(await engine.state == .live)
    }

    @Test func deltaSyncFollowsNextLinkUntilFinalDeltaLink() async throws {
        let db = try await makeDB()
        try await seedOutlookAccount(db)
        let api = MockGraphAPI()
        let nextLink = "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$skiptoken=opaque-next"
        api.deltaResults["folder:inbox"] = [
            .success(GraphDTO.MessageDeltaResponse(value: [], nextLink: nextLink))
        ]
        api.deltaResults["url:\(nextLink)"] = [
            .success(GraphDTO.MessageDeltaResponse(
                value: [
                    graphMessage(id: "m2", conversationId: "c2", parentFolderId: "inbox")
                ],
                deltaLink: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=opaque-delta"
            ))
        ]

        let engine = GraphMailSyncEngine(
            accountId: "outlook-1",
            api: api,
            db: db,
            configuration: GraphSyncConfiguration(isEnabled: true, selectedFolderIds: ["inbox"])
        )
        await engine.bootstrap()

        let calls = api.deltaCalls
        let checkpoint = try db.read { dbConn in
            try GraphDeltaCheckpointRecord.fetchOne(
                dbConn,
                key: ["account_id": "outlook-1", "folder_id": "inbox"]
            )
        }
        #expect(calls.count == 2)
        #expect(calls[0].deltaURL == nil)
        #expect(calls[1].deltaURL?.absoluteString == nextLink)
        #expect(checkpoint?.deltaURL.contains("opaque-delta") == true)
    }

    @Test func refreshUsesIsolatedFolderCheckpoints() async throws {
        let db = try await makeDB()
        try await seedOutlookAccount(db)
        let inboxCheckpoint = "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=inbox-old"
        let sentCheckpoint = "https://graph.microsoft.com/v1.0/me/mailFolders/sentitems/messages/delta?$deltatoken=sent-old"
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try GraphDeltaCheckpointRecord(
                    accountId: "outlook-1",
                    folderId: "inbox",
                    deltaURL: inboxCheckpoint,
                    updatedAt: 1
                ).insert(dbConn)
                try GraphDeltaCheckpointRecord(
                    accountId: "outlook-1",
                    folderId: "sentitems",
                    deltaURL: sentCheckpoint,
                    updatedAt: 1
                ).insert(dbConn)
            }
        }

        let api = MockGraphAPI()
        api.deltaResults["url:\(inboxCheckpoint)"] = [
            .success(GraphDTO.MessageDeltaResponse(
                value: [],
                deltaLink: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=inbox-new"
            ))
        ]
        api.deltaResults["url:\(sentCheckpoint)"] = [
            .success(GraphDTO.MessageDeltaResponse(
                value: [],
                deltaLink: "https://graph.microsoft.com/v1.0/me/mailFolders/sentitems/messages/delta?$deltatoken=sent-new"
            ))
        ]

        let engine = GraphMailSyncEngine(
            accountId: "outlook-1",
            api: api,
            db: db,
            configuration: GraphSyncConfiguration(isEnabled: true, selectedFolderIds: ["inbox", "sentitems"])
        )
        await engine.refresh()

        let calls = api.deltaCalls
        let checkpoints = try db.read { dbConn in
            try GraphDeltaCheckpointRecord
                .order(Column("folder_id"))
                .fetchAll(dbConn)
        }
        #expect(calls.map(\.deltaURL?.absoluteString) == [inboxCheckpoint, sentCheckpoint])
        #expect(checkpoints.map(\.folderId) == ["inbox", "sentitems"])
        #expect(checkpoints[0].deltaURL.contains("inbox-new"))
        #expect(checkpoints[1].deltaURL.contains("sent-new"))
    }

    @Test func deletionTombstoneRemovesMessageAndThreadWhenEmpty() async throws {
        let db = try await makeDB()
        try await seedOutlookAccount(db)
        let messageID = "outlook:outlook-1:message:m-delete"
        let threadID = "outlook:outlook-1:conversation:c-delete"
        let checkpoint = "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=old"
        try await DatabaseActor.shared.run {
            try db.write { dbConn in
                try ThreadRecord(id: threadID, accountId: "outlook-1", lastMessageAt: 100, messageCount: 1).insert(dbConn)
                try MessageRecord(id: messageID, threadId: threadID, accountId: "outlook-1", sentAt: 100).insert(dbConn)
                try ThreadLabelRecord(accountId: "outlook-1", threadId: threadID, labelId: "INBOX").insert(dbConn)
                try LocalSearchIndexPersistence.upsertMessage(accountId: "outlook-1", messageId: messageID, in: dbConn, now: 1)
                try GraphDeltaCheckpointRecord(accountId: "outlook-1", folderId: "inbox", deltaURL: checkpoint, updatedAt: 1)
                    .insert(dbConn)
            }
        }

        let api = MockGraphAPI()
        api.deltaResults["url:\(checkpoint)"] = [
            .success(GraphDTO.MessageDeltaResponse(
                value: [
                    GraphDTO.Message(
                        id: "m-delete",
                        parentFolderId: "inbox",
                        odataRemoved: GraphDTO.Removed(reason: "deleted")
                    )
                ],
                deltaLink: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=new"
            ))
        ]

        let engine = GraphMailSyncEngine(
            accountId: "outlook-1",
            api: api,
            db: db,
            configuration: GraphSyncConfiguration(isEnabled: true, selectedFolderIds: ["inbox"])
        )
        await engine.refresh()

        let remaining = try db.read { dbConn in
            (
                try MessageRecord.fetchOne(dbConn, key: ["account_id": "outlook-1", "id": messageID]),
                try ThreadRecord.fetchOne(dbConn, key: ["account_id": "outlook-1", "id": threadID]),
                try ThreadLabelRecord
                    .filter(Column("account_id") == "outlook-1" && Column("thread_id") == threadID)
                    .fetchCount(dbConn),
                try MailSearchDocumentRecord
                    .filter(Column("account_id") == "outlook-1" && Column("message_id") == messageID)
                    .fetchCount(dbConn)
            )
        }
        #expect(remaining.0 == nil)
        #expect(remaining.1 == nil)
        #expect(remaining.2 == 0)
        #expect(remaining.3 == 0)
    }

    @Test func rateLimitPausesGraphEngine() async throws {
        let db = try await makeDB()
        try await seedOutlookAccount(db)
        let api = MockGraphAPI()
        api.deltaResults["folder:inbox"] = [
            .failure(GraphAPIError.rateLimited(retryAfter: 2))
        ]

        let engine = GraphMailSyncEngine(
            accountId: "outlook-1",
            api: api,
            db: db,
            configuration: GraphSyncConfiguration(isEnabled: true, selectedFolderIds: ["inbox"])
        )
        await engine.bootstrap()

        #expect(await engine.state == .paused)
        await engine.stop()
    }

    @Test func authFailureDegradesGraphEngine() async throws {
        let db = try await makeDB()
        try await seedOutlookAccount(db)
        let api = MockGraphAPI()
        api.deltaResults["folder:inbox"] = [
            .failure(GraphAPIError.unauthorized)
        ]

        let engine = GraphMailSyncEngine(
            accountId: "outlook-1",
            api: api,
            db: db,
            configuration: GraphSyncConfiguration(isEnabled: true, selectedFolderIds: ["inbox"])
        )
        await engine.bootstrap()

        #expect(await engine.state == .degraded)
    }

    private func graphMessage(
        id: String,
        conversationId: String,
        parentFolderId: String,
        subject: String = "Subject",
        isRead: Bool = true,
        categories: [String] = [],
        isFlagged: Bool = false
    ) -> GraphDTO.Message {
        GraphDTO.Message(
            id: id,
            internetMessageId: "<\(id)@example.com>",
            conversationId: conversationId,
            parentFolderId: parentFolderId,
            subject: subject,
            bodyPreview: "Preview \(id)",
            body: GraphDTO.ItemBody(contentType: .text, content: "Body \(id)"),
            from: GraphDTO.Recipient(emailAddress: GraphDTO.EmailAddress(name: "Sender", address: "sender@example.com")),
            toRecipients: [
                GraphDTO.Recipient(emailAddress: GraphDTO.EmailAddress(address: "user@example.com"))
            ],
            receivedDateTime: "2026-05-29T10:00:00Z",
            sentDateTime: "2026-05-29T10:00:00Z",
            isRead: isRead,
            attachments: [
                GraphDTO.AttachmentMetadata(id: "a-\(id)", name: "file.txt", contentType: "text/plain", size: 7)
            ],
            categories: categories,
            flag: GraphDTO.FollowupFlag(flagStatus: isFlagged ? "flagged" : "notFlagged")
        )
    }
}

private final class MockGraphAPI: GraphAPI, @unchecked Sendable {
    struct DeltaCall: Sendable, Equatable {
        let folderId: String
        let deltaURL: URL?
        let pageSize: Int?
    }

    var folders = GraphDTO.MailFolderList(value: [
        GraphDTO.MailFolder(id: "inbox", displayName: "Inbox"),
        GraphDTO.MailFolder(id: "sentitems", displayName: "Sent Items"),
    ])
    var deltaResults: [String: [Result<GraphDTO.MessageDeltaResponse, GraphAPIError>]] = [:]
    private(set) var deltaCalls: [DeltaCall] = []

    func listFolders() async throws -> GraphDTO.MailFolderList {
        folders
    }

    func folderMessageDelta(
        folderId: String,
        deltaURL: URL?,
        pageSize: Int?
    ) async throws -> GraphDTO.MessageDeltaResponse {
        deltaCalls.append(DeltaCall(folderId: folderId, deltaURL: deltaURL, pageSize: pageSize))
        let key = deltaURL.map { "url:\($0.absoluteString)" } ?? "folder:\(folderId)"
        guard var queue = deltaResults[key], !queue.isEmpty else {
            throw GraphAPIError.invalidResponse
        }
        let result = queue.removeFirst()
        deltaResults[key] = queue
        return try result.get()
    }

    func getMessage(id: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func getAttachment(messageId: String, attachmentId: String) async throws -> GraphDTO.AttachmentContent {
        throw GraphAPIError.invalidResponse
    }

    func sendMail(_ request: GraphDTO.SendMailRequest) async throws -> GraphDTO.SendResult {
        throw GraphAPIError.invalidResponse
    }

    func markRead(messageId: String, isRead: Bool) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func moveMessage(messageId: String, destinationFolderId: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func archiveMessage(messageId: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func trashMessage(messageId: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func setFlag(messageId: String, isFlagged: Bool) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func updateCategories(messageId: String, categories: [String]) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }
}
