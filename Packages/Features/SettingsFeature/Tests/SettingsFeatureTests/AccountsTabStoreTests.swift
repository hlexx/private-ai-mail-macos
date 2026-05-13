import Testing
import Foundation
@testable import SettingsFeature
import AuthKit
import Persistence
import MailSync
import MailProviders
import GRDB

// MARK: - Mocks

final class MockOAuthClient: OAuthClient, @unchecked Sendable {
    var authorizeResult: Result<TokenCredential, Error> = .failure(AuthError.cancelled)

    func authorize() async throws -> TokenCredential {
        try authorizeResult.get()
    }

    func refresh(_ refreshToken: String) async throws -> TokenCredential {
        TokenCredential(
            accessToken: "refreshed",
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}

final class MockTokenStore: TokenStore, @unchecked Sendable {
    var storage: [String: TokenCredential] = [:]
    var deleteCalledWith: [String] = []

    func save(_ credential: TokenCredential, for accountID: String) throws {
        storage[accountID] = credential
    }

    func load(for accountID: String) throws -> TokenCredential? {
        storage[accountID]
    }

    func delete(for accountID: String) throws {
        storage.removeValue(forKey: accountID)
        deleteCalledWith.append(accountID)
    }
}

final class MockGmailAPI: GmailAPI, @unchecked Sendable {
    func listMessages(query: String?, pageToken: String?, maxResults: Int) async throws -> GmailDTO.MessageList {
        GmailDTO.MessageList(messages: [], nextPageToken: nil, resultSizeEstimate: 0)
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
}

// MARK: - Helpers

private func insertAccount(id: String, email: String, into db: AppDatabase) throws {
    let account = AccountRecord(
        id: id,
        provider: "gmail",
        email: email,
        createdAt: Int(Date().timeIntervalSince1970)
    )
    try db.dbQueue.write { dbConn in
        try account.insert(dbConn)
    }
}

// MARK: - Tests

@Suite("AccountsTabStore")
struct AccountsTabStoreTests {

    private func makeStore(
        db: AppDatabase? = nil,
        oauthClient: MockOAuthClient? = nil,
        tokenStore: MockTokenStore? = nil
    ) async throws -> (AccountsTabStore, AppDatabase, MockOAuthClient, MockTokenStore) {
        let database = try db ?? AppDatabase.openInMemorySync()
        let oauth = oauthClient ?? MockOAuthClient()
        let tokens = tokenStore ?? MockTokenStore()
        let supervisor = SyncSupervisor(db: database) { _ in MockGmailAPI() }
        let store = await AccountsTabStore(
            db: database,
            oauthClient: oauth,
            tokenStore: tokens,
            syncSupervisor: supervisor
        )
        return (store, database, oauth, tokens)
    }

    @Test @MainActor
    func addAccountCancelledResetsToIdle() async throws {
        let (store, _, oauth, _) = try await makeStore()

        oauth.authorizeResult = .failure(AuthError.cancelled)

        store.addGmailAccount()
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.addPhase == .idle)
    }

    @Test @MainActor
    func addAccountErrorSurfacesMessage() async throws {
        let (store, _, oauth, _) = try await makeStore()

        oauth.authorizeResult = .failure(AuthError.denied)

        store.addGmailAccount()
        try await Task.sleep(for: .milliseconds(200))

        if case .error = store.addPhase {
            // Error surfaced correctly
        } else {
            Issue.record("Expected error phase, got \(store.addPhase)")
        }
    }

    @Test @MainActor
    func dismissErrorResetsToIdle() async throws {
        let (store, _, oauth, _) = try await makeStore()

        oauth.authorizeResult = .failure(AuthError.denied)

        store.addGmailAccount()
        try await Task.sleep(for: .milliseconds(200))

        store.dismissError()
        #expect(store.addPhase == .idle)
    }

    @Test @MainActor
    func removeAccountDeletesFromDBAndKeychain() async throws {
        let (store, db, _, tokens) = try await makeStore()

        let accountId = "test-account-id"
        try insertAccount(id: accountId, email: "test@gmail.com", into: db)
        try tokens.save(
            TokenCredential(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture),
            for: accountId
        )

        store.startObserving()
        try await Task.sleep(for: .milliseconds(300))

        #expect(store.accounts.count == 1)

        store.removeAccount(accountId)
        try await Task.sleep(for: .milliseconds(500))

        let remaining = try db.read { db in
            try AccountRecord.fetchAll(db)
        }
        #expect(remaining.isEmpty)
        #expect(tokens.deleteCalledWith.contains(accountId))

        store.stopObserving()
    }

    @Test @MainActor
    func observingPicksUpExistingAccounts() async throws {
        let (store, db, _, _) = try await makeStore()

        try insertAccount(id: "existing-1", email: "existing@gmail.com", into: db)

        store.startObserving()
        try await Task.sleep(for: .milliseconds(300))

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.email == "existing@gmail.com")

        store.stopObserving()
    }

    @Test @MainActor
    func addSuccessMovesToFetchingProfile() async throws {
        let (store, _, oauth, _) = try await makeStore()

        oauth.authorizeResult = .success(TokenCredential(
            accessToken: "test-access",
            refreshToken: "test-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        ))

        store.addGmailAccount()
        try await Task.sleep(for: .milliseconds(500))

        // After authorize, it tries fetchUserEmail which will fail (no network in tests).
        // The phase should be either fetchingProfile or error.
        switch store.addPhase {
        case .fetchingProfile, .error:
            break // Expected
        default:
            Issue.record("Expected fetchingProfile or error phase, got \(store.addPhase)")
        }
    }
}
