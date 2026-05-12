import Testing
@testable import BriefFeature

@Suite("BriefFeature")
struct BriefFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(BriefFeature.moduleName == "BriefFeature")
    }
}
