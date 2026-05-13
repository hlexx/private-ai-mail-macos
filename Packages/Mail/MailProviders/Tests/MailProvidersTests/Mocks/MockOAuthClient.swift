import Foundation
import AuthKit

final class MockOAuthClient: OAuthClient, @unchecked Sendable {
    var refreshResult: TokenCredential?
    var refreshError: Error?
    var refreshCallCount = 0

    func authorize() async throws -> TokenCredential {
        fatalError("Not used in tests")
    }

    func refresh(_ refreshToken: String) async throws -> TokenCredential {
        refreshCallCount += 1
        if let error = refreshError { throw error }
        guard let result = refreshResult else { fatalError("No refresh result set") }
        return result
    }
}
