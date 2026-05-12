import Testing
@testable import ActionsFeature

@Suite("ActionsFeature")
struct ActionsFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ActionsFeature.moduleName == "ActionsFeature")
    }
}
