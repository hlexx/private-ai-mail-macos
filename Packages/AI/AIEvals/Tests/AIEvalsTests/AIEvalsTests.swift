import Testing
@testable import AIEvals

@Suite("AIEvals")
struct AIEvalsTests {
    @Test func moduleNameIsExported() {
        #expect(AIEvals.moduleName == "AIEvals")
    }
}
