import Testing
@testable import ComposeFeature

@Suite("ComposeFeature")
struct ComposeFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ComposeFeature.moduleName == "ComposeFeature")
    }
}
