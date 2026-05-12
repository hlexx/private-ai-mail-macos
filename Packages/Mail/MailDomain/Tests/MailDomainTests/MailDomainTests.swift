import Testing
@testable import MailDomain

@Suite("MailDomain")
struct MailDomainTests {
    @Test func moduleNameIsExported() {
        #expect(MailDomain.moduleName == "MailDomain")
    }
}
