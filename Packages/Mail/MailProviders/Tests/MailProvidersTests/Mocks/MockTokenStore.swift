import Foundation
import AuthKit

final class MockTokenStore: TokenStore, @unchecked Sendable {
    private var storage: [String: TokenCredential] = [:]

    func save(_ credential: TokenCredential, for accountID: String) throws {
        storage[accountID] = credential
    }

    func load(for accountID: String) throws -> TokenCredential? {
        storage[accountID]
    }

    func delete(for accountID: String) throws {
        storage.removeValue(forKey: accountID)
    }
}
