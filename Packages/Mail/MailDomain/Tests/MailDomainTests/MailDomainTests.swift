import Testing
@testable import MailDomain

@Suite("MailDomain")
struct MailDomainTests {
    @Test func addressParsingRFC822() {
        let addr = Address(rfc822: "Alice Smith <alice@example.com>")
        #expect(addr?.name == "Alice Smith")
        #expect(addr?.email == "alice@example.com")
    }

    @Test func addressParsingPlain() {
        let addr = Address(rfc822: "bob@example.com")
        #expect(addr?.name == nil)
        #expect(addr?.email == "bob@example.com")
    }
}
