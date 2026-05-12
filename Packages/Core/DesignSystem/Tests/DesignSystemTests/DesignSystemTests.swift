import Testing
@testable import DesignSystem

@Suite("DesignSystem")
struct DesignSystemTests {
    @Test func moduleNameIsExported() {
        #expect(DesignSystem.moduleName == "DesignSystem")
    }
}
