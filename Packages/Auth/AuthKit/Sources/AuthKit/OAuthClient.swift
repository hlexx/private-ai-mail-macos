import Foundation

public protocol OAuthClient: Sendable {
    func authorize() async throws -> TokenCredential
    func refresh(_ refreshToken: String) async throws -> TokenCredential
}
