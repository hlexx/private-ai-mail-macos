import Testing
@testable import AIRuntime

@Suite("AIRuntime")
struct AIRuntimeTests {
    @Test func moduleNameIsExported() {
        #expect(AIRuntime.moduleName == "AIRuntime")
    }
}
