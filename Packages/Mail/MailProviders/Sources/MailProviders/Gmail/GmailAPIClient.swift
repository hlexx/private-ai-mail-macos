import AuthKit
import Foundation

public final class GmailAPIClient: GmailAPI, @unchecked Sendable {
    private let session: URLSession
    private let oauthClient: any OAuthClient
    private let accountId: String
    private let tokenStore: any TokenStore
    private let rateLimiter = RateLimiter()
    private let lock = NSLock()
    private var _credential: TokenCredential?
    private var _refreshTask: Task<TokenCredential, Error>?

    private static let maxRetries = 5
    private static let baseBackoffMs: UInt64 = 500
    private static let maxTotalBackoff: TimeInterval = 30

    public init(
        accountId: String,
        credential: TokenCredential,
        oauthClient: any OAuthClient,
        tokenStore: any TokenStore,
        session: URLSession? = nil
    ) {
        self.accountId = accountId
        self._credential = credential
        self.oauthClient = oauthClient
        self.tokenStore = tokenStore
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

    private var credential: TokenCredential? {
        get { lock.withLock { _credential } }
        set { lock.withLock { _credential = newValue } }
    }

    // MARK: - GmailAPI

    public func listMessages(query: String?, pageToken: String?, maxResults: Int) async throws -> GmailDTO.MessageList {
        let endpoint = GmailEndpoint.listMessages(query: query, pageToken: pageToken, maxResults: maxResults)
        return try await perform(endpoint)
    }

    public func getMessage(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Message {
        let endpoint = GmailEndpoint.getMessage(id: id, format: format)
        return try await perform(endpoint)
    }

    public func getThread(id: String, format: GmailMessageFormat) async throws -> GmailDTO.Thread {
        let endpoint = GmailEndpoint.getThread(id: id, format: format)
        return try await perform(endpoint)
    }

    public func listHistory(startHistoryId: String, pageToken: String?) async throws -> GmailDTO.HistoryResponse {
        let endpoint = GmailEndpoint.listHistory(startHistoryId: startHistoryId, pageToken: pageToken)
        return try await perform(endpoint)
    }

    public func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage {
        let endpoint = GmailEndpoint.sendMessage(raw: base64URL, threadId: threadId)
        return try await perform(endpoint)
    }

    public func listLabels() async throws -> [GmailDTO.Label] {
        let endpoint = GmailEndpoint.listLabels
        let response: GmailDTO.LabelList = try await perform(endpoint)
        return response.labels ?? []
    }

    // MARK: - Request execution

    private func perform<T: Decodable & Sendable>(_ endpoint: GmailEndpoint) async throws -> T {
        await rateLimiter.acquire(units: endpoint.quotaCost)
        return try await executeWithRetry(
            url: endpoint.url,
            httpMethod: endpoint.httpMethod,
            httpBody: endpoint.httpBody,
            quotaCost: endpoint.quotaCost,
            attempt: 0,
            totalWaited: 0
        )
    }

    private func executeWithRetry<T: Decodable & Sendable>(
        url: URL,
        httpMethod: String,
        httpBody: Data?,
        quotaCost: Int,
        attempt: Int,
        totalWaited: TimeInterval,
        didRefresh: Bool = false
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        if let httpBody {
            request.httpBody = httpBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let cred = credential {
            request.setValue("\(cred.tokenType) \(cred.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GmailAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                throw GmailAPIError.decodingError(error)
            }

        case 401:
            guard !didRefresh else {
                throw GmailAPIError.unauthorized
            }
            return try await handleUnauthorized(
                url: url, httpMethod: httpMethod, httpBody: httpBody, quotaCost: quotaCost
            )

        case 403:
            if isInsufficientScope(data) {
                throw GmailAPIError.insufficientScope
            }
            throw GmailAPIError.serverError(statusCode: 403)

        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            return try await handleRetryable(
                url: url,
                httpMethod: httpMethod,
                httpBody: httpBody,
                quotaCost: quotaCost,
                statusCode: 429,
                retryAfter: retryAfter,
                attempt: attempt,
                totalWaited: totalWaited
            )

        case 500...599:
            // POST requests are not idempotent — the server may have
            // already processed the send before returning 5xx. Only
            // retry safe (GET) methods to avoid duplicate emails.
            guard httpMethod == "GET" else {
                throw GmailAPIError.serverError(statusCode: httpResponse.statusCode)
            }
            return try await handleRetryable(
                url: url,
                httpMethod: httpMethod,
                httpBody: httpBody,
                quotaCost: quotaCost,
                statusCode: httpResponse.statusCode,
                retryAfter: nil,
                attempt: attempt,
                totalWaited: totalWaited
            )

        default:
            throw GmailAPIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    private func isInsufficientScope(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let errors = error["errors"] as? [[String: Any]] else {
            return false
        }
        return errors.contains { ($0["reason"] as? String) == "insufficientPermissions" }
    }

    private func handleUnauthorized<T: Decodable & Sendable>(
        url: URL, httpMethod: String, httpBody: Data?, quotaCost: Int
    ) async throws -> T {
        let task: Task<TokenCredential, Error> = lock.withLock {
            if let existing = _refreshTask {
                return existing
            }
            let refreshTask = Task<TokenCredential, Error> { [oauthClient, tokenStore, accountId] in
                guard let cred = self.credential else {
                    throw GmailAPIError.unauthorized
                }
                let newCredential = try await oauthClient.refresh(cred.refreshToken)
                self.credential = newCredential
                try tokenStore.save(newCredential, for: accountId)
                return newCredential
            }
            _refreshTask = refreshTask
            return refreshTask
        }

        do {
            _ = try await task.value
            lock.withLock { _refreshTask = nil }
        } catch {
            lock.withLock { _refreshTask = nil }
            throw error
        }

        await rateLimiter.acquire(units: quotaCost)
        return try await executeWithRetry(
            url: url, httpMethod: httpMethod, httpBody: httpBody,
            quotaCost: quotaCost, attempt: 0, totalWaited: 0, didRefresh: true
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func handleRetryable<T: Decodable & Sendable>(
        url: URL,
        httpMethod: String,
        httpBody: Data?,
        quotaCost: Int,
        statusCode: Int,
        retryAfter: TimeInterval?,
        attempt: Int,
        totalWaited: TimeInterval
    ) async throws -> T {
        guard attempt < Self.maxRetries else {
            if statusCode == 429 {
                throw GmailAPIError.rateLimited(retryAfter: retryAfter)
            }
            throw GmailAPIError.exhaustedRetries
        }

        let delay: TimeInterval
        if let retryAfter {
            delay = min(retryAfter, Self.maxTotalBackoff - totalWaited)
        } else {
            let backoff = Double(Self.baseBackoffMs) * pow(2.0, Double(attempt)) / 1000.0
            let jitter = Double.random(in: 0...0.5)
            delay = backoff + jitter
        }

        guard delay > 0, totalWaited + delay <= Self.maxTotalBackoff else {
            if statusCode == 429 {
                throw GmailAPIError.rateLimited(retryAfter: retryAfter)
            }
            throw GmailAPIError.exhaustedRetries
        }

        try await Task.sleep(for: .milliseconds(Int(delay * 1000)))

        await rateLimiter.acquire(units: quotaCost)
        return try await executeWithRetry(
            url: url, httpMethod: httpMethod, httpBody: httpBody,
            quotaCost: quotaCost, attempt: attempt + 1, totalWaited: totalWaited + delay
        )
    }
}
