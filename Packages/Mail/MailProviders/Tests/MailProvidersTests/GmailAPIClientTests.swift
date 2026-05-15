import Testing
import Foundation
@testable import MailProviders
import AuthKit

@Suite("GmailAPIClient", .serialized)
struct GmailAPIClientTests {
    let accountId = "test-account"

    func makeCredential(accessToken: String = "access-token", refreshToken: String = "refresh-token") -> TokenCredential {
        TokenCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date.distantFuture
        )
    }

    func makeClient(
        credential: TokenCredential? = nil,
        oauthClient: MockOAuthClient = MockOAuthClient(),
        tokenStore: MockTokenStore = MockTokenStore()
    ) -> GmailAPIClient {
        GmailAPIClient(
            accountId: accountId,
            credential: credential ?? makeCredential(),
            oauthClient: oauthClient,
            tokenStore: tokenStore,
            session: MockURLProtocol.makeSession()
        )
    }

    // MARK: - listMessages happy path

    @Test func listMessagesHappyPath() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub(
            path: "/messages",
            json: """
            {
              "messages": [
                {"id": "msg001", "threadId": "thread001"},
                {"id": "msg002", "threadId": "thread001"}
              ],
              "nextPageToken": "token123",
              "resultSizeEstimate": 2
            }
            """
        )

        let client = makeClient()
        let result = try await client.listMessages(query: nil, pageToken: nil, maxResults: 10)

        #expect(result.messages?.count == 2)
        #expect(result.messages?[0].id == "msg001")
        #expect(result.nextPageToken == "token123")
    }

    // MARK: - 401 → refresh → retry → 200

    @Test func unauthorizedTriggersRefreshAndRetry() async throws {
        MockURLProtocol.reset()

        let oauthClient = MockOAuthClient()
        let newCred = makeCredential(accessToken: "new-access-token")
        oauthClient.refreshResult = newCred

        let tokenStore = MockTokenStore()

        MockURLProtocol.stubSequence(
            path: "/messages",
            responses: [
                (statusCode: 401, json: "{\"error\": \"unauthorized\"}", headers: ["Content-Type": "application/json"]),
                (statusCode: 200, json: """
                    {"messages": [{"id": "msg001", "threadId": "t1"}], "resultSizeEstimate": 1}
                    """, headers: ["Content-Type": "application/json"])
            ]
        )

        let client = makeClient(oauthClient: oauthClient, tokenStore: tokenStore)
        let result = try await client.listMessages(query: nil, pageToken: nil, maxResults: 10)

        #expect(result.messages?.count == 1)
        #expect(oauthClient.refreshCallCount == 1)

        let stored = try tokenStore.load(for: accountId)
        #expect(stored?.accessToken == "new-access-token")
    }

    // MARK: - 429 → backoff → success within budget

    @Test func rateLimitedTriggersBackoffAndRetry() async throws {
        MockURLProtocol.reset()

        MockURLProtocol.stubSequence(
            path: "/messages",
            responses: [
                (statusCode: 429, json: "{\"error\": \"rate limited\"}", headers: ["Content-Type": "application/json", "Retry-After": "1"]),
                (statusCode: 200, json: """
                    {"messages": [{"id": "msg001", "threadId": "t1"}], "resultSizeEstimate": 1}
                    """, headers: ["Content-Type": "application/json"])
            ]
        )

        let client = makeClient()
        let result = try await client.listMessages(query: nil, pageToken: nil, maxResults: 10)

        #expect(result.messages?.count == 1)
    }

    // MARK: - sendMessage happy path

    @Test func sendMessageHappyPath() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub(
            path: "/messages/send",
            json: """
            {"id": "19abc123def45678", "threadId": "19abc123def00000", "labelIds": ["SENT"]}
            """
        )

        let client = makeClient()
        let result = try await client.sendMessage(raw: "dGVzdA", threadId: nil)

        #expect(result.id == "19abc123def45678")
        #expect(result.threadId == "19abc123def00000")
        #expect(result.labelIds == ["SENT"])
    }

    // MARK: - sendMessage 403 insufficient scope

    @Test func sendMessageInsufficientScopeThrows() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub(
            path: "/messages/send",
            statusCode: 403,
            json: """
            {
              "error": {
                "errors": [{"domain": "global", "reason": "insufficientPermissions", "message": "Insufficient Permission"}],
                "code": 403,
                "message": "Insufficient Permission"
              }
            }
            """
        )

        let client = makeClient()

        do {
            _ = try await client.sendMessage(raw: "dGVzdA", threadId: nil)
            Issue.record("Expected GmailAPIError.insufficientScope")
        } catch GmailAPIError.insufficientScope {
            // expected
        } catch {
            Issue.record("Expected insufficientScope, got \(error)")
        }
    }

    // MARK: - sendMessage 401 → refresh → retry → 200

    @Test func sendMessageUnauthorizedTriggersRefreshAndRetry() async throws {
        MockURLProtocol.reset()

        let oauthClient = MockOAuthClient()
        let newCred = makeCredential(accessToken: "refreshed-token")
        oauthClient.refreshResult = newCred

        let tokenStore = MockTokenStore()

        MockURLProtocol.stubSequence(
            path: "/messages/send",
            responses: [
                (statusCode: 401, json: "{\"error\": \"unauthorized\"}", headers: ["Content-Type": "application/json"]),
                (statusCode: 200, json: """
                    {"id": "sent001", "threadId": "thread001", "labelIds": ["SENT"]}
                    """, headers: ["Content-Type": "application/json"])
            ]
        )

        let client = makeClient(oauthClient: oauthClient, tokenStore: tokenStore)
        let result = try await client.sendMessage(raw: "dGVzdA", threadId: "thread001")

        #expect(result.id == "sent001")
        #expect(oauthClient.refreshCallCount == 1)
        let stored = try tokenStore.load(for: accountId)
        #expect(stored?.accessToken == "refreshed-token")
    }

    // MARK: - sendMessage network isolation (exactly one request)

    @Test func sendMessageIssuesExactlyOneRequest() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.stub(
            path: "/messages/send",
            json: """
            {"id": "iso001", "threadId": "tiso001", "labelIds": ["SENT"]}
            """
        )

        let client = makeClient()
        _ = try await client.sendMessage(raw: "dGVzdA", threadId: nil)

        let sendRequests = MockURLProtocol.requestLog.filter {
            $0.url?.path.contains("/messages/send") == true
        }
        #expect(sendRequests.count == 1, "sendMessage must issue exactly one outbound request")
        #expect(MockURLProtocol.requestLog.count == 1, "No implicit follow-ups or telemetry requests")
    }

    // MARK: - sendMessage 429 → backoff → retry → 200

    @Test func sendMessageRateLimitedRetries() async throws {
        MockURLProtocol.reset()

        MockURLProtocol.stubSequence(
            path: "/messages/send",
            responses: [
                (statusCode: 429, json: "{\"error\": \"rate limited\"}", headers: ["Content-Type": "application/json", "Retry-After": "1"]),
                (statusCode: 200, json: """
                    {"id": "sent002", "threadId": "thread002"}
                    """, headers: ["Content-Type": "application/json"])
            ]
        )

        let client = makeClient()
        let result = try await client.sendMessage(raw: "dGVzdA", threadId: nil)

        #expect(result.id == "sent002")
    }
}

@Suite("GmailMapper")
struct GmailMapperTests {
    let accountId = "test-account"

    @Test func mapMessageMetadata() async throws {
        let dto = GmailDTO.Message(
            id: "msg001",
            threadId: "thread001",
            labelIds: ["INBOX", "UNREAD"],
            snippet: "Hey, just checking in...",
            historyId: "12345",
            internalDate: "1700000000000",
            payload: GmailDTO.MessagePart(
                mimeType: "multipart/alternative",
                headers: [
                    GmailDTO.MessagePartHeader(name: "From", value: "Alice Smith <alice@example.com>"),
                    GmailDTO.MessagePartHeader(name: "To", value: "bob@example.com, Charlie <charlie@example.com>"),
                    GmailDTO.MessagePartHeader(name: "Cc", value: "dave@example.com"),
                    GmailDTO.MessagePartHeader(name: "Subject", value: "Quick check-in"),
                    GmailDTO.MessagePartHeader(name: "Message-ID", value: "<abc123@mail.example.com>"),
                ]
            )
        )

        let message = GmailMapper.mapMessage(dto, accountId: accountId)

        #expect(message.id == "msg001")
        #expect(message.threadId == "thread001")
        #expect(message.from?.email == "alice@example.com")
        #expect(message.from?.name == "Alice Smith")
        #expect(message.to.count == 2)
        #expect(message.to[0].email == "bob@example.com")
        #expect(message.to[1].email == "charlie@example.com")
        #expect(message.cc.count == 1)
        #expect(message.cc[0].email == "dave@example.com")
        #expect(message.messageIdHeader == "<abc123@mail.example.com>")
        #expect(message.isUnread == true)
        #expect(message.sentAt == Date(timeIntervalSince1970: 1700000000))
    }

    @Test func mapMessageFull() async throws {
        let dto = GmailDTO.Message(
            id: "msg001",
            threadId: "thread001",
            labelIds: ["INBOX"],
            snippet: "Hey",
            internalDate: "1700000000000",
            payload: GmailDTO.MessagePart(
                mimeType: "multipart/alternative",
                headers: [
                    GmailDTO.MessagePartHeader(name: "From", value: "alice@example.com"),
                ],
                parts: [
                    GmailDTO.MessagePart(
                        partId: "0",
                        mimeType: "text/plain",
                        body: GmailDTO.MessagePartBody(size: 22, data: "SGVsbG8gV29ybGQ")
                    ),
                    GmailDTO.MessagePart(
                        partId: "1",
                        mimeType: "text/html",
                        body: GmailDTO.MessagePartBody(size: 30, data: "PHA-SGVsbG88L3A-")
                    ),
                ]
            )
        )

        let message = GmailMapper.mapMessage(dto, accountId: accountId)

        #expect(message.bodyText == "Hello World")
        #expect(message.bodyHTML != nil)
        #expect(message.isUnread == false)
    }

    @Test func mapMessageWithAttachment() async throws {
        let dto = GmailDTO.Message(
            id: "msg002",
            threadId: "thread001",
            labelIds: [],
            internalDate: "1700000000000",
            payload: GmailDTO.MessagePart(
                mimeType: "multipart/mixed",
                headers: [],
                parts: [
                    GmailDTO.MessagePart(
                        partId: "0",
                        mimeType: "text/plain",
                        body: GmailDTO.MessagePartBody(size: 5, data: "SGk")
                    ),
                    GmailDTO.MessagePart(
                        partId: "1",
                        mimeType: "application/pdf",
                        filename: "report.pdf",
                        body: GmailDTO.MessagePartBody(attachmentId: "att001", size: 1024)
                    ),
                ]
            )
        )

        let message = GmailMapper.mapMessage(dto, accountId: accountId)

        #expect(message.attachments.count == 1)
        #expect(message.attachments[0].id == "att001")
        #expect(message.attachments[0].filename == "report.pdf")
        #expect(message.attachments[0].mimeType == "application/pdf")
    }
}
