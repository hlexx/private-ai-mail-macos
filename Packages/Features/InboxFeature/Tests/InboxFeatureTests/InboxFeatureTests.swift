import Testing
@testable import InboxFeature

@Suite("InboxFeature")
struct InboxFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(InboxFeature.moduleName == "InboxFeature")
    }
}
