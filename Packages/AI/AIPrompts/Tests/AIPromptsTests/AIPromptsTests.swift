import Testing
@testable import AIPrompts

@Suite("AIPrompts")
struct AIPromptsTests {
    @Test func moduleNameIsExported() {
        #expect(AIPrompts.moduleName == "AIPrompts")
    }
}
