import Testing
@testable import SettingsFeature

@Suite("SettingsFeature")
struct SettingsFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(SettingsFeature.moduleName == "SettingsFeature")
    }
}
