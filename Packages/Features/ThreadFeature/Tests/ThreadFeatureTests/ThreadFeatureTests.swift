import Testing
@testable import ThreadFeature

@Suite("ThreadFeature")
struct ThreadFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ThreadFeature.moduleName == "ThreadFeature")
    }
}
