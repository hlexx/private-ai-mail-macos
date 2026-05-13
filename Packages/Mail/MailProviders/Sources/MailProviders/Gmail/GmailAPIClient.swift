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

    // MARK: - Request execution

    private func perform<T: Decodable & Sendable>(_ endpoint: GmailEndpoint) async throws -> T {
        await rateLimiter.acquire(units: endpoint.quotaCost)
        return try await executeWithRetry(endpoint.url, quotaCost: endpoint.quotaCost, attempt: 0, totalWaited: 0)
    }

    private func executeWithRetry<T: Decodable & Sendable>(
        _ url: URL,
        quotaCost: Int,
        attempt: Int,
        totalWaited: TimeInterval,
        didRefresh: Bool = false
    ) async throws -> T {
        var request = URLRequest(url: url)
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
            return try await handleUnauthorized(url: url, quotaCost: quotaCost)

        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            return try await handleRetryable(
                url: url,
                quotaCost: quotaCost,
                statusCode: 429,
                retryAfter: retryAfter,
                attempt: attempt,
                totalWaited: totalWaited
            )

        case 500...599:
            return try await handleRetryable(
                url: url,
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

    private func handleUnauthorized<T: Decodable & Sendable>(url: URL, quotaCost: Int) async throws -> T {
        // Coalesce concurrent refresh attempts into a single task
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
        return try await executeWithRetry(url, quotaCost: quotaCost, attempt: 0, totalWaited: 0, didRefresh: true)
    }

    private func handleRetryable<T: Decodable & Sendable>(
        url: URL,
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
        return try await executeWithRetry(url, quotaCost: quotaCost, attempt: attempt + 1, totalWaited: totalWaited + delay)
    }
}
