import Foundation
import MailDomain
import Testing
@testable import MailProviders

@Suite("ProviderSendExecution", .serialized)
struct ProviderSendExecutionTests {
    @Test func gmailExecutorBuildsMimeAndReturnsProviderNeutralResult() async throws {
        let api = MockSendGmailAPI()
        api.sendMessageResult = .success(
            GmailDTO.SentMessage(id: "gmail-message-1", threadId: "gmail-thread-1", labelIds: ["SENT"])
        )
        let sentAt = Date(timeIntervalSince1970: 100)
        let executor = GmailSendExecutor(api: api, now: { sentAt })

        let result = try await executor.send(
            ProviderSendRequest(
                provider: .gmail,
                accountID: "account-1",
                idempotencyKey: "idem-1",
                from: Address(name: "Me", email: "me@example.com"),
                to: [Address(name: "Recipient", email: "recipient@example.com")],
                cc: [Address(email: "cc@example.com")],
                subject: "Trust send",
                bodyText: "Hello, provider.",
                threadID: "gmail-thread-1",
                rfcMessageID: "<custom@example.com>",
                rfcInReplyTo: "<parent@example.com>",
                rfcReferences: ["<root@example.com>"]
            )
        )

        #expect(api.sendCallCount == 1)
        #expect(api.lastThreadID == "gmail-thread-1")
        #expect(result.provider == .gmail)
        #expect(result.providerMessageID == "gmail-message-1")
        #expect(result.providerThreadID == "gmail-thread-1")
        #expect(result.rfcMessageID == "<custom@example.com>")
        #expect(result.sentAt == sentAt)

        let raw = try decodedRawMessage(api.lastRaw)
        #expect(raw.contains("Message-ID: <custom@example.com>\r\n"))
        #expect(raw.contains("To: Recipient <recipient@example.com>\r\n"))
        #expect(raw.contains("Cc: cc@example.com\r\n"))
        #expect(raw.contains("In-Reply-To: <parent@example.com>\r\n"))
        #expect(raw.contains("References: <root@example.com> <parent@example.com>\r\n"))
        #expect(raw.contains("Hello, provider."))
    }

    @Test func gmailExecutorUsesIdempotencyKeyForStableMessageIDWhenRequestHasNoHeader() async throws {
        let api = MockSendGmailAPI()
        let executor = GmailSendExecutor(api: api, now: { Date(timeIntervalSince1970: 200) })

        let result = try await executor.send(
            ProviderSendRequest(
                provider: .gmail,
                accountID: "account-1",
                idempotencyKey: "idem-stable",
                from: Address(email: "me@example.com"),
                to: [Address(email: "recipient@example.com")],
                subject: "Stable",
                bodyText: "Body"
            )
        )

        let raw = try decodedRawMessage(api.lastRaw)
        #expect(raw.contains("Message-ID: <idem-stable@hlexx.privateaimail>\r\n"))
        #expect(result.rfcMessageID == "<idem-stable@hlexx.privateaimail>")
    }

    @Test func gmailExecutorMapsProviderFailureToSanitizedSendFailure() async throws {
        let api = MockSendGmailAPI()
        api.sendMessageResult = .failure(GmailAPIError.insufficientScope)
        let occurredAt = Date(timeIntervalSince1970: 300)
        let executor = GmailSendExecutor(api: api, now: { occurredAt })

        do {
            _ = try await executor.send(basicRequest(provider: .gmail))
            Issue.record("Expected ProviderSendError")
        } catch let error as ProviderSendError {
            #expect(error.failure.category == .insufficientScope)
            #expect(error.failure.providerErrorCode == "insufficient_scope")
            #expect(error.failure.occurredAt == occurredAt)
        } catch {
            Issue.record("Expected ProviderSendError, got \(error)")
        }
    }

    @Test func graphExecutorBuildsSendMailRequestAndReturnsAcceptedResult() async throws {
        let api = MockSendGraphAPI()
        api.sendMailResult = .success(
            GraphDTO.SendResult(accepted: true, statusCode: 202, requestId: "graph-request-1")
        )
        let sentAt = Date(timeIntervalSince1970: 400)
        let executor = GraphSendExecutor(api: api, now: { sentAt })

        let result = try await executor.send(
            ProviderSendRequest(
                provider: .outlook,
                accountID: "account-2",
                idempotencyKey: "idem-graph",
                from: Address(email: "me@example.com"),
                to: [Address(name: "Recipient", email: "recipient@example.com")],
                cc: [Address(email: "cc@example.com")],
                bcc: [Address(email: "bcc@example.com")],
                subject: "Graph send",
                bodyHTML: "<p>Hello Graph</p>"
            )
        )

        let request = try #require(api.lastSendMailRequest)
        #expect(api.sendMailCallCount == 1)
        #expect(request.saveToSentItems)
        #expect(request.message.subject == "Graph send")
        #expect(request.message.body?.contentType == .html)
        #expect(request.message.body?.content == "<p>Hello Graph</p>")
        #expect(request.message.from == nil)
        #expect(request.message.toRecipients?.first?.emailAddress.address == "recipient@example.com")
        #expect(request.message.ccRecipients?.first?.emailAddress.address == "cc@example.com")
        #expect(request.message.bccRecipients?.first?.emailAddress.address == "bcc@example.com")
        #expect(result.provider == .outlook)
        #expect(result.providerMessageID == nil)
        #expect(result.providerRequestID == "graph-request-1")
        #expect(result.sentAt == sentAt)
    }

    @Test func graphExecutorMapsProviderFailureToSanitizedSendFailure() async throws {
        let api = MockSendGraphAPI()
        api.sendMailResult = .failure(GraphAPIError.rateLimited(retryAfter: 42))
        let occurredAt = Date(timeIntervalSince1970: 500)
        let executor = GraphSendExecutor(api: api, now: { occurredAt })

        do {
            _ = try await executor.send(basicRequest(provider: .outlook))
            Issue.record("Expected ProviderSendError")
        } catch let error as ProviderSendError {
            #expect(error.failure.category == .rateLimited)
            #expect(error.failure.providerErrorCode == "429")
            #expect(error.failure.retryAfterSeconds == 42)
            #expect(error.failure.occurredAt == occurredAt)
        } catch {
            Issue.record("Expected ProviderSendError, got \(error)")
        }
    }

    private func basicRequest(provider: MailProviderIdentifier) -> ProviderSendRequest {
        ProviderSendRequest(
            provider: provider,
            accountID: "account-basic",
            idempotencyKey: "idem-basic",
            from: Address(email: "me@example.com"),
            to: [Address(email: "recipient@example.com")],
            subject: "Basic",
            bodyText: "Body"
        )
    }

    private func decodedRawMessage(_ raw: String?) throws -> String {
        let raw = try #require(raw)
        let data = try #require(MIMEBuilder.base64URLDecode(raw))
        return try #require(String(data: data, encoding: .utf8))
    }
}

private final class MockSendGmailAPI: GmailAPI, @unchecked Sendable {
    var sendMessageResult: Result<GmailDTO.SentMessage, Error> = .success(
        GmailDTO.SentMessage(id: "sent-default", threadId: "thread-default", labelIds: ["SENT"])
    )
    private(set) var sendCallCount = 0
    private(set) var lastRaw: String?
    private(set) var lastThreadID: String?

    func listMessages(query: String?, pageToken: String?, maxResults: Int) async throws -> GmailDTO.MessageList {
        GmailDTO.MessageList(messages: nil, nextPageToken: nil)
    }

    func getMessage(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Message {
        throw GmailAPIError.invalidResponse
    }

    func getThread(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Thread {
        throw GmailAPIError.invalidResponse
    }

    func listHistory(startHistoryId: String, pageToken: String?) async throws -> GmailDTO.HistoryResponse {
        GmailDTO.HistoryResponse(history: nil, nextPageToken: nil, historyId: startHistoryId)
    }

    func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage {
        sendCallCount += 1
        lastRaw = base64URL
        lastThreadID = threadId
        return try sendMessageResult.get()
    }

    func createDraft(raw base64URL: String, threadId: String?) async throws -> GmailDTO.Draft {
        throw GmailAPIError.invalidResponse
    }

    func listLabels() async throws -> [GmailDTO.Label] {
        []
    }

    func modifyThread(id: String, addLabelIds: [String], removeLabelIds: [String]) async throws -> GmailDTO.Thread {
        throw GmailAPIError.invalidResponse
    }
}

private final class MockSendGraphAPI: GraphAPI, @unchecked Sendable {
    var sendMailResult: Result<GraphDTO.SendResult, Error> = .success(
        GraphDTO.SendResult(accepted: true, statusCode: 202, requestId: "request-default")
    )
    private(set) var sendMailCallCount = 0
    private(set) var lastSendMailRequest: GraphDTO.SendMailRequest?

    func listFolders() async throws -> GraphDTO.MailFolderList {
        throw GraphAPIError.invalidResponse
    }

    func folderMessageDelta(folderId: String, deltaURL: URL?, pageSize: Int?) async throws -> GraphDTO.MessageDeltaResponse {
        throw GraphAPIError.invalidResponse
    }

    func getMessage(id: String) async throws -> GraphDTO.Message {
        throw GraphAPIError.invalidResponse
    }

    func getAttachment(messageId: String, attachmentId: String) async throws -> GraphDTO.AttachmentContent {
        throw GraphAPIError.invalidResponse
    }

    func sendMail(_ request: GraphDTO.SendMailRequest) async throws -> GraphDTO.SendResult {
        sendMailCallCount += 1
        lastSendMailRequest = request
        return try sendMailResult.get()
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
