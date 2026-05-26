import Foundation
import Testing
@testable import AuthKit

@Suite("AuthKit")
struct AuthKitTests {
    @Test func moduleNameIsExported() {
        #expect(AuthKit.moduleName == "AuthKit")
    }

    @Test func defaultScopesIncludeReadSendAndUserinfo() {
        let expected: Set<String> = [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.send",
            "https://www.googleapis.com/auth/userinfo.email"
        ]
        let actual = Set(GmailOAuthConfig.default.scopes)
        #expect(actual == expected)
    }
}

@Suite("PKCE")
struct PKCETests {
    @Test func verifierLengthIs43() {
        let challenge = PKCE.generate()
        #expect(challenge.verifier.count == 43)
    }

    @Test func verifierIsBase64URLSafe() {
        let challenge = PKCE.generate()
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        for scalar in challenge.verifier.unicodeScalars {
            #expect(allowed.contains(scalar))
        }
    }

    @Test func challengeMethodIsS256() {
        let challenge = PKCE.generate()
        #expect(challenge.method == "S256")
    }

    @Test func challengeIsBase64URLSafe() {
        let challenge = PKCE.generate()
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        for scalar in challenge.challenge.unicodeScalars {
            #expect(allowed.contains(scalar))
        }
    }

    @Test func challengeIsDeterministicForSameVerifier() {
        let c1 = PKCE.computeChallenge(from: "test_verifier_string")
        let c2 = PKCE.computeChallenge(from: "test_verifier_string")
        #expect(c1 == c2)
    }

    @Test func rfc7636TestVector() {
        // RFC 7636 Appendix B test vector
        // verifier: dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
        // expected S256 challenge: E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let result = PKCE.computeChallenge(from: verifier)
        #expect(result == expected)
    }

    @Test func differentVerifiersProduceDifferentChallenges() {
        let c1 = PKCE.computeChallenge(from: "verifier_one")
        let c2 = PKCE.computeChallenge(from: "verifier_two")
        #expect(c1 != c2)
    }
}

@Suite("InMemoryTokenStore")
struct InMemoryTokenStoreTests {
    @Test func saveAndLoad() throws {
        let store = InMemoryTokenStore()
        let cred = makeCredential()
        try store.save(cred, for: "acct1")
        let loaded = try store.load(for: "acct1")
        #expect(loaded?.accessToken == cred.accessToken)
        #expect(loaded?.refreshToken == cred.refreshToken)
    }

    @Test func loadMissingReturnsNil() throws {
        let store = InMemoryTokenStore()
        let loaded = try store.load(for: "nonexistent")
        #expect(loaded == nil)
    }

    @Test func deleteRemovesEntry() throws {
        let store = InMemoryTokenStore()
        try store.save(makeCredential(), for: "acct1")
        try store.delete(for: "acct1")
        let loaded = try store.load(for: "acct1")
        #expect(loaded == nil)
    }

    @Test func saveOverwritesExisting() throws {
        let store = InMemoryTokenStore()
        try store.save(makeCredential(access: "old"), for: "acct1")
        try store.save(makeCredential(access: "new"), for: "acct1")
        let loaded = try store.load(for: "acct1")
        #expect(loaded?.accessToken == "new")
    }

    @Test func multipleAccounts() throws {
        let store = InMemoryTokenStore()
        try store.save(makeCredential(access: "a"), for: "acct1")
        try store.save(makeCredential(access: "b"), for: "acct2")
        #expect(try store.load(for: "acct1")?.accessToken == "a")
        #expect(try store.load(for: "acct2")?.accessToken == "b")
    }

    private func makeCredential(access: String = "at") -> TokenCredential {
        TokenCredential(
            accessToken: access,
            refreshToken: "rt",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}

@Suite("ReauthorizeScopes")
struct ReauthorizeScopeTests {
    @Test(arguments: [
        (
            label: "default config includes gmail.send",
            additionalScopes: [] as [String],
            mustContain: ["gmail.send", "gmail.readonly", "userinfo.email"]
        ),
        (
            label: "adding gmail.compose merges with defaults",
            additionalScopes: ["https://www.googleapis.com/auth/gmail.compose"],
            mustContain: ["gmail.send", "gmail.readonly", "gmail.compose"]
        ),
        (
            label: "duplicate scope is deduplicated",
            additionalScopes: ["https://www.googleapis.com/auth/gmail.send"],
            mustContain: ["gmail.send", "gmail.readonly"]
        ),
    ])
    func reauthorizeScopesMergeCorrectly(
        label: String, additionalScopes: [String], mustContain: [String]
    ) {
        let config = GmailOAuthConfig.default
        let merged = Set(config.scopes + additionalScopes)
        for keyword in mustContain {
            let found = merged.contains { $0.contains(keyword) }
            #expect(found, "Expected merged scopes to contain '\(keyword)' — \(label)")
        }
    }

    @Test func duplicateScopesAreDeduped() {
        let config = GmailOAuthConfig.default
        let additional = ["https://www.googleapis.com/auth/gmail.send"]
        let merged = Array(Set(config.scopes + additional))
        let sendCount = merged.filter { $0.contains("gmail.send") }.count
        #expect(sendCount == 1)
    }
}

@Suite("RefreshRequestBody", .serialized)
struct RefreshRequestBodyTests {
    @Test func refreshSendsActualRequiredBodyAndDecodesSuccess() async throws {
        let client = makeClient(
            session: OAuthRefreshURLProtocol.makeSession(
                statusCode: 200,
                body: #"{"access_token":"new_access_token","expires_in":3600,"token_type":"Bearer"}"#
            )
        )

        let credential = try await client.refresh("test_refresh_token")
        let encoded = OAuthRefreshURLProtocol.capturedBodyString() ?? ""

        #expect(encoded.contains("client_id=test_client_id"))
        #expect(encoded.contains("refresh_token=test_refresh_token"))
        #expect(encoded.contains("grant_type=refresh_token"))
        #expect(credential.accessToken == "new_access_token")
        #expect(credential.refreshToken == "test_refresh_token")
    }

    @Test func refreshThrowsInvalidResponseForNonSuccessStatus() async throws {
        let client = makeClient(
            session: OAuthRefreshURLProtocol.makeSession(
                statusCode: 500,
                body: #"{"error":"server_error"}"#
            )
        )

        do {
            _ = try await client.refresh("test_refresh_token")
            Issue.record("Expected refresh failure")
        } catch AuthError.invalidResponse {
        } catch {
            Issue.record("Expected invalidResponse, got \(error)")
        }
    }

    @Test func refreshSurfacesMalformedTokenResponse() async throws {
        let client = makeClient(
            session: OAuthRefreshURLProtocol.makeSession(
                statusCode: 200,
                body: #"{"access_token":42}"#
            )
        )

        do {
            _ = try await client.refresh("test_refresh_token")
            Issue.record("Expected decoding failure")
        } catch is DecodingError {
        } catch {
            Issue.record("Expected DecodingError, got \(error)")
        }
    }

    @Test func urlEncodingHandlesSpecialChars() {
        let body: [String: String] = [
            "value": "hello world"
        ]
        let encoded = String(data: body.urlEncodedData, encoding: .utf8)!
        #expect(encoded.contains("hello%20world"))
    }

    private func makeClient(session: URLSession) -> GmailOAuthClient {
        GmailOAuthClient(
            config: GmailOAuthConfig(
                clientID: "test_client_id",
                redirectURI: "test:/oauth2callback",
                scopes: []
            ),
            urlSession: session
        )
    }
}

@Suite("TokenCredential")
struct TokenCredentialTests {
    @Test func notExpiredWhenInFuture() {
        let cred = TokenCredential(
            accessToken: "at",
            refreshToken: "rt",
            expiresAt: Date().addingTimeInterval(3600)
        )
        #expect(!cred.isExpired)
    }

    @Test func expiredWhenInPast() {
        let cred = TokenCredential(
            accessToken: "at",
            refreshToken: "rt",
            expiresAt: Date().addingTimeInterval(-1)
        )
        #expect(cred.isExpired)
    }
}

// MARK: - Helpers

final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func save(_ credential: TokenCredential, for accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[accountID] = try JSONEncoder().encode(credential)
    }

    func load(for accountID: String) throws -> TokenCredential? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = storage[accountID] else { return nil }
        return try JSONDecoder().decode(TokenCredential.self, from: data)
    }

    func delete(for accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: accountID)
    }
}

private final class OAuthRefreshURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseStatusCode = 200
    nonisolated(unsafe) private static var responseBody = Data()
    nonisolated(unsafe) private static var capturedBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let requestBody = request.httpBody ?? Self.data(from: request.httpBodyStream)
        Self.lock.lock()
        Self.capturedBody = requestBody
        let statusCode = Self.responseStatusCode
        let body = Self.responseBody
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func data(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    static func makeSession(statusCode: Int, body: String) -> URLSession {
        lock.lock()
        responseStatusCode = statusCode
        responseBody = Data(body.utf8)
        capturedBody = nil
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAuthRefreshURLProtocol.self]
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    static func capturedBodyString() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return capturedBody.map { String(decoding: $0, as: UTF8.self) }
    }
}
