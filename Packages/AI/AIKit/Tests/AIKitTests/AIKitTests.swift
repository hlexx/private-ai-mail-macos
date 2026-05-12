import Testing
@testable import AIKit

@Suite("AIKit")
struct AIKitTests {
    @Test func moduleNameIsExported() {
        #expect(AIKit.moduleName == "AIKit")
    }
}
