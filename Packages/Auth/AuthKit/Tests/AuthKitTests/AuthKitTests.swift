import Foundation
import Testing
@testable import AuthKit

@Suite("AuthKit")
struct AuthKitTests {
    @Test func moduleNameIsExported() {
        #expect(AuthKit.moduleName == "AuthKit")
    }

    @Test func defaultScopesIncludeReadMetadataSendAndUserinfo() {
        let expected: Set<String> = [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.metadata",
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
            mustContain: ["gmail.send", "gmail.readonly", "gmail.metadata", "userinfo.email"]
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

@Suite("RefreshRequestBody")
struct RefreshRequestBodyTests {
    @Test func refreshBodyContainsRequiredFields() {
        let body: [String: String] = [
            "client_id": "test_client_id",
            "refresh_token": "test_refresh_token",
            "grant_type": "refresh_token",
        ]
        let encoded = String(data: body.urlEncodedData, encoding: .utf8)!

        #expect(encoded.contains("client_id=test_client_id"))
        #expect(encoded.contains("refresh_token=test_refresh_token"))
        #expect(encoded.contains("grant_type=refresh_token"))
    }

    @Test func urlEncodingHandlesSpecialChars() {
        let body: [String: String] = [
            "value": "hello world"
        ]
        let encoded = String(data: body.urlEncodedData, encoding: .utf8)!
        #expect(encoded.contains("hello%20world"))
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

