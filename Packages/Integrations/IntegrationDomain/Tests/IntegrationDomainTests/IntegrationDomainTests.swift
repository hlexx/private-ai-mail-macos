import Testing
@testable import IntegrationDomain

@Suite("IntegrationDomain")
struct IntegrationDomainTests {
    @Test func moduleNameIsExported() {
        #expect(IntegrationDomain.moduleName == "IntegrationDomain")
    }
}
