import Testing
@testable import MailProviders

@Suite("MailProviders")
struct MailProvidersTests {
    @Test func moduleNameIsExported() {
        #expect(MailProviders.moduleName == "MailProviders")
    }
}
