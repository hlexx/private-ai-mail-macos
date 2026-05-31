import Foundation

public struct GraphAPIClientEvent: Sendable, Equatable, CustomStringConvertible {
    public let method: String
    public let endpoint: String
    public let statusCode: Int?
    public let retryAfter: TimeInterval?

    public init(method: String, endpoint: String, statusCode: Int? = nil, retryAfter: TimeInterval? = nil) {
        self.method = method
        self.endpoint = endpoint
        self.statusCode = statusCode
        self.retryAfter = retryAfter
    }

    public var description: String {
        var parts = ["method=\(method)", "endpoint=\(endpoint)"]
        if let statusCode {
            parts.append("status=\(statusCode)")
        }
        if let retryAfter {
            parts.append("retryAfter=\(Int(retryAfter))")
        }
        return "GraphAPIClientEvent(\(parts.joined(separator: " ")))"
    }
}

public final class GraphAPIClient: GraphAPI, @unchecked Sendable {
    public typealias AccessTokenProvider = @Sendable () async throws -> String
    public typealias EventSink = @Sendable (GraphAPIClientEvent) -> Void

    private let session: URLSession
    private let accessTokenProvider: AccessTokenProvider
    private let eventSink: EventSink?
    private let decoder = JSONDecoder()

    public init(
        accessTokenProvider: @escaping AccessTokenProvider,
        session: URLSession? = nil,
        eventSink: EventSink? = nil
    ) {
        self.accessTokenProvider = accessTokenProvider
        self.eventSink = eventSink
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.httpAdditionalHeaders = [:]
            self.session = URLSession(configuration: config)
        }
    }

    public convenience init(
        accessToken: String,
        session: URLSession? = nil,
        eventSink: EventSink? = nil
    ) {
        self.init(accessTokenProvider: { accessToken }, session: session, eventSink: eventSink)
    }

    public func listFolders() async throws -> GraphDTO.MailFolderList {
        try await perform(.listFolders)
    }

    public func folderMessageDelta(folderId: String, deltaURL: URL?, pageSize: Int?) async throws -> GraphDTO.MessageDeltaResponse {
        try await perform(.folderMessageDelta(folderId: folderId, deltaURL: deltaURL, pageSize: pageSize))
    }

    public func getMessage(id: String) async throws -> GraphDTO.Message {
        try await perform(.getMessage(id: id))
    }

    public func getAttachment(messageId: String, attachmentId: String) async throws -> GraphDTO.AttachmentContent {
        guard Self.hasValue(messageId), Self.hasValue(attachmentId) else {
            throw GraphAPIError.missingAttachmentIdentifier
        }
        return try await perform(.getAttachment(messageId: messageId, attachmentId: attachmentId))
    }

    public func sendMail(_ request: GraphDTO.SendMailRequest) async throws -> GraphDTO.SendResult {
        try await performEmpty(.sendMail(request))
    }

    public func markRead(messageId: String, isRead: Bool) async throws -> GraphDTO.Message {
        try await perform(.markRead(messageId: messageId, isRead: isRead))
    }

    public func moveMessage(messageId: String, destinationFolderId: String) async throws -> GraphDTO.Message {
        try await perform(.moveMessage(messageId: messageId, destinationFolderId: destinationFolderId))
    }

    public func archiveMessage(messageId: String) async throws -> GraphDTO.Message {
        try await perform(.archiveMessage(messageId: messageId))
    }

    public func trashMessage(messageId: String) async throws -> GraphDTO.Message {
        try await perform(.trashMessage(messageId: messageId))
    }

    public func setFlag(messageId: String, isFlagged: Bool) async throws -> GraphDTO.Message {
        try await perform(.setFlag(messageId: messageId, isFlagged: isFlagged))
    }

    public func updateCategories(messageId: String, categories: [String]) async throws -> GraphDTO.Message {
        try await perform(.updateCategories(messageId: messageId, categories: categories))
    }

    private func perform<T: Decodable & Sendable>(_ endpoint: GraphEndpoint) async throws -> T {
        let (data, _) = try await execute(endpoint)
        guard !data.isEmpty else {
            throw GraphAPIError.invalidResponse
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GraphAPIError.decodingError(String(describing: error))
        }
    }

    private func performEmpty(_ endpoint: GraphEndpoint) async throws -> GraphDTO.SendResult {
        let (_, response) = try await execute(endpoint)
        return GraphDTO.SendResult(
            accepted: (200..<300).contains(response.statusCode),
            statusCode: response.statusCode,
            requestId: response.value(forHTTPHeaderField: "request-id")
        )
    }

    private func execute(_ endpoint: GraphEndpoint) async throws -> (Data, HTTPURLResponse) {
        let token: String
        do {
            token = try await accessTokenProvider()
        } catch {
            throw GraphAPIError.unauthorized
        }

        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.httpMethod
        request.setValue(["Bearer", token].joined(separator: " "), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = endpoint.httpBody {
            request.httpBody = body
        }

        eventSink?(GraphAPIClientEvent(method: endpoint.httpMethod, endpoint: endpoint.name.rawValue))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GraphAPIError.networkError(String(describing: error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GraphAPIError.invalidResponse
        }

        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        eventSink?(
            GraphAPIClientEvent(
                method: endpoint.httpMethod,
                endpoint: endpoint.name.rawValue,
                statusCode: httpResponse.statusCode,
                retryAfter: retryAfter
            )
        )

        switch httpResponse.statusCode {
        case 200..<300:
            return (data, httpResponse)
        case 401:
            throw GraphAPIError.unauthorized
        case 403:
            if isInsufficientScope(data) {
                throw GraphAPIError.insufficientScope
            }
            throw GraphAPIError.serverError(statusCode: 403, code: graphErrorCode(data))
        case 429:
            throw GraphAPIError.rateLimited(retryAfter: retryAfter)
        default:
            throw GraphAPIError.serverError(statusCode: httpResponse.statusCode, code: graphErrorCode(data))
        }
    }

    private func isInsufficientScope(_ data: Data) -> Bool {
        let code = graphErrorCode(data)?.lowercased()
        return code == "authorization_requestdenied"
            || code == "erroraccessdenied"
            || code == "invalid_grant"
            || code == "invalidscope"
    }

    private func graphErrorCode(_ data: Data) -> String? {
        guard !data.isEmpty,
              let response = try? decoder.decode(GraphDTO.ErrorResponse.self, from: data) else {
            return nil
        }
        return response.error.code
    }

    private static func hasValue(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
