import Testing
@testable import Persistence

@Suite("Persistence")
struct PersistenceTests {
    @Test func moduleNameIsExported() {
        #expect(Persistence.moduleName == "Persistence")
    }
}
