import Foundation

public protocol TokenStore: Sendable {
    func save(_ credential: TokenCredential, for accountID: String) throws
    func load(for accountID: String) throws -> TokenCredential?
    func delete(for accountID: String) throws
}
