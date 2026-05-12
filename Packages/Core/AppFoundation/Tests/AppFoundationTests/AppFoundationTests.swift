import Testing
@testable import AppFoundation

@Suite("AppFoundation")
struct AppFoundationTests {
    @Test func moduleNameIsExported() {
        #expect(AppFoundation.moduleName == "AppFoundation")
    }
}
