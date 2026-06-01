import Foundation
import Testing
@testable import MailProviders

@Suite("GraphAPIClient", .serialized)
struct GraphAPIClientTests {
    @Test func listFoldersDecodesAndInjectsBearerAuth() async throws {
        GraphMockURLProtocol.reset()
        let capture = RequestCapture()
        GraphMockURLProtocol.handlers.append { request in
            guard request.url?.path.contains("/me/mailFolders") == true else { return nil }
            capture.recordAuthorization(request.value(forHTTPHeaderField: "Authorization"))
            let data = """
            {
              "value": [
                {
                  "id": "folder-1",
                  "displayName": "Inbox",
                  "parentFolderId": "root",
                  "childFolderCount": 1,
                  "unreadItemCount": 2,
                  "totalItemCount": 3
                }
              ]
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }

        let client = GraphAPIClient(accessToken: "graph-access-token", session: GraphMockURLProtocol.makeSession())
        let result = try await client.listFolders()

        #expect(result.value.count == 1)
        #expect(result.value[0].id == "folder-1")
        #expect(result.value[0].displayName == "Inbox")
        #expect(capture.authorization == "Bearer graph-access-token")
    }

    @Test func folderDeltaDecodesNextAndDeltaLinks() async throws {
        GraphMockURLProtocol.reset()
        GraphMockURLProtocol.stub(
            path: "/messages/delta",
            json: """
            {
              "value": [
                {
                  "id": "message-1",
                  "subject": "Quarterly trust review",
                  "body": {"contentType": "html", "content": "<p>Ready</p>"},
                  "from": {"emailAddress": {"name": "Alice", "address": "alice@example.com"}},
                  "toRecipients": [{"emailAddress": {"address": "bob@example.com"}}],
                  "isRead": false,
                  "hasAttachments": true,
                  "categories": ["Important"],
                  "flag": {"flagStatus": "flagged"},
                  "attachments": [
                    {
                      "@odata.type": "#microsoft.graph.fileAttachment",
                      "id": "attachment-1",
                      "name": "brief.pdf",
                      "contentType": "application/pdf",
                      "size": 2048
                    }
                  ]
                }
              ],
              "@odata.nextLink": "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$skiptoken=opaque-next",
              "@odata.deltaLink": "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=opaque-delta"
            }
            """
        )

        let client = GraphAPIClient(accessToken: "token", session: GraphMockURLProtocol.makeSession())
        let result = try await client.folderMessageDelta(folderId: "inbox", deltaURL: nil, pageSize: 50)

        #expect(result.value.count == 1)
        #expect(result.value[0].body?.contentType == .html)
        #expect(result.value[0].from?.emailAddress.address == "alice@example.com")
        #expect(result.value[0].attachments?.first?.name == "brief.pdf")
        #expect(result.nextLink?.contains("opaque-next") == true)
        #expect(result.deltaLink?.contains("opaque-delta") == true)
        let requestURL = try #require(GraphMockURLProtocol.requestLog.first?.url)
        let queryItems = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems
        #expect(queryItems?.contains(URLQueryItem(name: "$top", value: "50")) == true)
    }

    @Test func getAttachmentDataDecodesContentBytes() async throws {
        GraphMockURLProtocol.reset()
        GraphMockURLProtocol.stub(
            path: "/me/messages/graph-message/attachments/graph-attachment",
            json: """
            {
              "@odata.type": "#microsoft.graph.fileAttachment",
              "id": "graph-attachment",
              "name": "brief.txt",
              "contentType": "text/plain",
              "size": 11,
              "isInline": false,
              "contentBytes": "SGVsbG8tR3JhcGg="
            }
            """
        )

        let client = GraphAPIClient(accessToken: "token", session: GraphMockURLProtocol.makeSession())
        let data = try await client.getAttachmentData(messageId: "graph-message", attachmentId: "graph-attachment")

        #expect(String(data: data, encoding: .utf8) == "Hello-Graph")
        let requests = GraphMockURLProtocol.requestLog.filter {
            $0.url?.path.contains("/me/messages/graph-message/attachments/graph-attachment") == true
        }
        #expect(requests.count == 1)
    }

    @Test func getAttachmentRejectsMissingIdentifierBeforeNetwork() async throws {
        GraphMockURLProtocol.reset()
        let client = GraphAPIClient(accessToken: "token", session: GraphMockURLProtocol.makeSession())

        do {
            _ = try await client.getAttachment(messageId: "graph-message", attachmentId: " ")
            Issue.record("Expected GraphAPIError.missingAttachmentIdentifier")
        } catch GraphAPIError.missingAttachmentIdentifier {
            // expected
        } catch {
            Issue.record("Expected missingAttachmentIdentifier, got \(error)")
        }

        #expect(GraphMockURLProtocol.requestLog.isEmpty)
    }

    @Test func getAttachmentNotFoundIsUserActionable() async throws {
        GraphMockURLProtocol.reset()
        GraphMockURLProtocol.stub(
            path: "/me/messages/graph-message/attachments/missing",
            statusCode: 404,
            json: """
            {"error": {"code": "ErrorItemNotFound", "message": "Attachment not found."}}
            """
        )

        let client = GraphAPIClient(accessToken: "token", session: GraphMockURLProtocol.makeSession())

        do {
            _ = try await client.getAttachment(messageId: "graph-message", attachmentId: "missing")
            Issue.record("Expected GraphAPIError.serverError")
        } catch GraphAPIError.serverError(let statusCode, let code) {
            #expect(statusCode == 404)
            #expect(code == "ErrorItemNotFound")
            #expect(GraphAPIError.serverError(statusCode: statusCode, code: code).sharedCategory == .notFound)
            #expect(GraphAPIError.serverError(statusCode: statusCode, code: code).errorDescription?.contains("Re-sync") == true)
        } catch {
            Issue.record("Expected serverError, got \(error)")
        }
    }

    @Test func graphErrorBodyMapsInsufficientScope() async throws {
        GraphMockURLProtocol.reset()
        GraphMockURLProtocol.stub(
            path: "/me/mailFolders",
            statusCode: 403,
            json: """
            {
              "error": {
                "code": "ErrorAccessDenied",
                "message": "Access is denied."
              }
            }
            """
        )

        let client = GraphAPIClient(accessToken: "token", session: GraphMockURLProtocol.makeSession())

        do {
            _ = try await client.listFolders()
            Issue.record("Expected GraphAPIError.insufficientScope")
        } catch GraphAPIError.insufficientScope {
            // expected
        } catch {
            Issue.record("Expected insufficientScope, got \(error)")
        }
    }

    @Test func rateLimitMapsRetryAfter() async throws {
        GraphMockURLProtocol.reset()
        GraphMockURLProtocol.stub(
            path: "/me/mailFolders",
            statusCode: 429,
            json: """
            {"error": {"code": "TooManyRequests", "message": "Please retry later."}}
            """,
            headers: ["Content-Type": "application/json", "Retry-After": "42"]
        )

        let client = GraphAPIClient(accessToken: "token", session: GraphMockURLProtocol.makeSession())

        do {
            _ = try await client.listFolders()
            Issue.record("Expected GraphAPIError.rateLimited")
        } catch GraphAPIError.rateLimited(let retryAfter) {
            #expect(retryAfter == 42)
        } catch {
            Issue.record("Expected rateLimited, got \(error)")
        }
    }

    @Test func authFailureMapsUnauthorized() async throws {
        GraphMockURLProtocol.reset()
        GraphMockURLProtocol.stub(
            path: "/me/mailFolders",
            statusCode: 401,
            json: """
            {"error": {"code": "InvalidAuthenticationToken", "message": "Token expired."}}
            """
        )

        let client = GraphAPIClient(accessToken: "expired-token", session: GraphMockURLProtocol.makeSession())

        do {
            _ = try await client.listFolders()
            Issue.record("Expected GraphAPIError.unauthorized")
        } catch GraphAPIError.unauthorized {
            // expected
        } catch {
            Issue.record("Expected unauthorized, got \(error)")
        }
    }

    @Test func serverErrorPreservesGraphCodeWithoutBodyLeak() async throws {
        GraphMockURLProtocol.reset()
        let eventRecorder = GraphEventRecorder()
        GraphMockURLProtocol.stub(
            path: "/me/mailFolders",
            statusCode: 503,
            json: """
            {"error": {"code": "ServiceUnavailable", "message": "private body token must not be logged"}}
            """
        )

        let client = GraphAPIClient(
            accessToken: "token",
            session: GraphMockURLProtocol.makeSession(),
            eventSink: eventRecorder.record
        )

        do {
            _ = try await client.listFolders()
            Issue.record("Expected GraphAPIError.serverError")
        } catch GraphAPIError.serverError(let statusCode, let code) {
            #expect(statusCode == 503)
            #expect(code == "ServiceUnavailable")
        } catch {
            Issue.record("Expected serverError, got \(error)")
        }

        let descriptions = eventRecorder.descriptions.joined(separator: "\n")
        #expect(descriptions.contains("listFolders"))
        #expect(!descriptions.contains("private body token"))
        #expect(!descriptions.contains("ServiceUnavailable"))
    }

    @Test func privacySafeEventsDoNotExposeDeltaURLTokenOrMailContent() async throws {
        GraphMockURLProtocol.reset()
        let eventRecorder = GraphEventRecorder()
        let opaqueURL = try #require(
            URL(string: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=secret-delta-token")
        )
        GraphMockURLProtocol.stub(
            path: "/messages/delta",
            json: """
            {
              "value": [],
              "@odata.deltaLink": "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta?$deltatoken=next-secret"
            }
            """
        )

        let message = GraphDTO.Message(
            subject: "secret subject",
            body: GraphDTO.ItemBody(contentType: .html, content: "<p>secret html body</p>"),
            toRecipients: [
                GraphDTO.Recipient(emailAddress: GraphDTO.EmailAddress(address: "recipient@example.com"))
            ]
        )
        let client = GraphAPIClient(
            accessToken: "secret-access-token",
            session: GraphMockURLProtocol.makeSession(),
            eventSink: eventRecorder.record
        )

        _ = try await client.folderMessageDelta(folderId: "inbox", deltaURL: opaqueURL, pageSize: nil)

        GraphMockURLProtocol.reset()
        GraphMockURLProtocol.stub(path: "/me/sendMail", statusCode: 202, json: "")

        _ = try await client.sendMail(GraphDTO.SendMailRequest(message: message))

        let descriptions = eventRecorder.descriptions.joined(separator: "\n")
        #expect(descriptions.contains("folderMessageDelta"))
        #expect(descriptions.contains("sendMail"))
        #expect(!descriptions.contains("secret-delta-token"))
        #expect(!descriptions.contains("next-secret"))
        #expect(!descriptions.contains("secret-access-token"))
        #expect(!descriptions.contains("secret subject"))
        #expect(!descriptions.contains("secret html body"))
        #expect(!descriptions.contains("recipient@example.com"))
    }
}

private final class GraphMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handlers: [(URLRequest) -> (Data, HTTPURLResponse)?] = []
    nonisolated(unsafe) static var requestLog: [URLRequest] = []
    private static let logLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.logLock.lock()
        Self.requestLog.append(request)
        Self.logLock.unlock()
        for handler in Self.handlers {
            if let (data, response) = handler(request) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        handlers = []
        logLock.lock()
        requestLog = []
        logLock.unlock()
    }

    static func stub(
        path: String,
        statusCode: Int = 200,
        json: String,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) {
        handlers.append { request in
            guard let url = request.url, url.path.contains(path) else { return nil }
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
            return (data, response)
        }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GraphMockURLProtocol.self]
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _authorization: String?

    var authorization: String? {
        lock.lock()
        defer { lock.unlock() }
        return _authorization
    }

    func recordAuthorization(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        _authorization = value
    }
}

private final class GraphEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [GraphAPIClientEvent] = []

    var descriptions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events.map(\.description)
    }

    func record(_ event: GraphAPIClientEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }
}
