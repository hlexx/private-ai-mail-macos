import Testing
@testable import IntegrationBroker

@Suite("IntegrationBroker")
struct IntegrationBrokerTests {
    @Test func moduleNameIsExported() {
        #expect(IntegrationBroker.moduleName == "IntegrationBroker")
    }
}
