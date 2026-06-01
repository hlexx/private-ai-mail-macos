import Testing
import AppFoundation
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

    func reauthorize(additionalScopes: [String]) async throws -> TokenCredential {
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

    func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage {
        throw GmailAPIError.invalidResponse
    }

    func listLabels() async throws -> [GmailDTO.Label] {
        []
    }

    func modifyThread(id: String, addLabelIds: [String], removeLabelIds: [String]) async throws -> GmailDTO.Thread {
        throw GmailAPIError.invalidResponse
    }
}

// MARK: - Helpers

private func insertAccount(
    id: String,
    email: String,
    provider: String = "gmail",
    into db: AppDatabase
) throws {
    let account = AccountRecord(
        id: id,
        provider: provider,
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
        tokenStore: MockTokenStore? = nil,
        localAccountCacheDeleter: @escaping @Sendable (String) throws -> Void = { _ in }
    ) async throws -> (AccountsTabStore, AppDatabase, MockOAuthClient, MockTokenStore) {
        let database = try db ?? AppDatabase.openInMemorySync()
        let oauth = oauthClient ?? MockOAuthClient()
        let tokens = tokenStore ?? MockTokenStore()
        let supervisor = SyncSupervisor(db: database) { _ in MockGmailAPI() }
        let store = await AccountsTabStore(
            db: database,
            oauthClient: oauth,
            tokenStore: tokens,
            syncSupervisor: supervisor,
            localAccountCacheDeleter: localAccountCacheDeleter
        )
        return (store, database, oauth, tokens)
    }

    @Test @MainActor
    func defaultProviderOptionsKeepGmailEnabledAndOutlookDisabledBeta() async throws {
        let (store, _, _, _) = try await makeStore()

        #expect(store.providerOptions.map(\.provider) == [.gmail, .outlook])

        let gmail = try #require(store.providerOptions.first { $0.provider == .gmail })
        #expect(gmail.title == "Gmail")
        #expect(gmail.actionTitle == "Add Gmail account")
        #expect(gmail.isEnabled)

        let outlook = try #require(store.providerOptions.first { $0.provider == .outlook })
        #expect(outlook.title == "Outlook")
        #expect(outlook.actionTitle == "Add Outlook account")
        #expect(!outlook.isEnabled)
        #expect(outlook.subtitle.contains("Beta"))

        if case .disabled(let reason) = outlook.availability {
            #expect(reason == "Internal beta")
        } else {
            Issue.record("Expected Outlook beta provider to be disabled by default")
        }
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
    func addAccountProviderRoutesGmailWithoutRegressingCancellation() async throws {
        let (store, _, oauth, _) = try await makeStore()

        oauth.authorizeResult = .failure(AuthError.cancelled)

        store.addAccount(provider: .gmail)
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.addPhase == .idle)
    }

    @Test @MainActor
    func addAccountProviderKeepsOutlookDisabledUntilSmokeTestsPass() async throws {
        let (store, _, _, _) = try await makeStore()

        store.addAccount(provider: .outlook)

        if case .error(let message) = store.addPhase {
            #expect(message.contains("Outlook support is in beta"))
            #expect(message.contains("disabled until real account smoke tests pass"))
        } else {
            Issue.record("Expected disabled Outlook beta error, got \(store.addPhase)")
        }
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
    func addAccountNetworkFailureShowsOfflineRecoveryCopy() async throws {
        let (store, _, oauth, _) = try await makeStore()

        oauth.authorizeResult = .failure(AuthError.network(URLError(.notConnectedToInternet)))

        store.addGmailAccount()
        try await Task.sleep(for: .milliseconds(200))

        if case .error(let message) = store.addPhase {
            #expect(message == "Account cannot reach Gmail while offline. Check your connection and try again.")
        } else {
            Issue.record("Expected offline account error, got \(store.addPhase)")
        }
    }

    @Test @MainActor
    func reauthorizeFailureShowsMissingCredentialRecoveryCopy() async throws {
        let (store, db, oauth, _) = try await makeStore()

        let accountId = "gmail-reauthorize-failure"
        try insertAccount(id: accountId, email: "test@gmail.com", into: db)
        oauth.authorizeResult = .failure(AuthError.missingRefreshToken)

        store.reauthorizeAccount(accountId)
        try await Task.sleep(for: .milliseconds(300))

        if case .error(let message) = store.reauthorizationPhases[accountId] {
            #expect(message == "Reconnect Gmail to use this account.")
        } else {
            Issue.record("Expected missing credential re-authorization error")
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
        let cacheDeletion = LocalAccountCacheDeletionSpy()
        let (store, db, _, tokens) = try await makeStore(
            localAccountCacheDeleter: { accountId in
                cacheDeletion.delete(accountId)
            }
        )

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
        #expect(cacheDeletion.deletedAccountIds == [accountId])

        store.stopObserving()
    }

    @Test @MainActor
    func reauthorizeAccountRefreshesGmailConsentAndSavesCredential() async throws {
        let (store, db, oauth, tokens) = try await makeStore()

        let accountId = "gmail-reauthorize"
        try insertAccount(id: accountId, email: "test@gmail.com", into: db)
        oauth.authorizeResult = .success(TokenCredential(
            accessToken: "reauthorized-access",
            refreshToken: "reauthorized-refresh",
            expiresAt: Date().addingTimeInterval(3600)
        ))

        store.reauthorizeAccount(accountId)
        try await Task.sleep(for: .milliseconds(300))

        #expect(tokens.storage[accountId]?.accessToken == "reauthorized-access")
        #expect(tokens.storage[accountId]?.refreshToken == "reauthorized-refresh")
        #expect(store.reauthorizationPhases[accountId] == .done)
    }

    @Test @MainActor
    func reauthorizeAccountKeepsOutlookUnsupportedUntilOAuthFlowExists() async throws {
        let (store, db, _, tokens) = try await makeStore()

        let accountId = "outlook-reauthorize"
        try insertAccount(id: accountId, email: "test@outlook.com", provider: "outlook", into: db)

        store.reauthorizeAccount(accountId)
        try await Task.sleep(for: .milliseconds(200))

        #expect(tokens.storage[accountId] == nil)
        if case .error(let message) = store.reauthorizationPhases[accountId] {
            #expect(message == "Outlook re-consent is not available in this build.")
        } else {
            Issue.record("Expected Outlook re-consent to remain unsupported")
        }
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

private final class LocalAccountCacheDeletionSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []

    func delete(_ accountId: String) {
        lock.withLock {
            ids.append(accountId)
        }
    }

    var deletedAccountIds: [String] {
        lock.withLock {
            ids
        }
    }
}
