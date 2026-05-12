import Testing
@testable import AuthKit

@Suite("AuthKit")
struct AuthKitTests {
    @Test func moduleNameIsExported() {
        #expect(AuthKit.moduleName == "AuthKit")
    }
}
