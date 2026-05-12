import Testing
@testable import IntegrationConnectors

@Suite("IntegrationConnectors")
struct IntegrationConnectorsTests {
    @Test func moduleNameIsExported() {
        #expect(IntegrationConnectors.moduleName == "IntegrationConnectors")
    }
}
