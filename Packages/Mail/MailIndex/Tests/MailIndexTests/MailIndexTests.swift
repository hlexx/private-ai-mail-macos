import Testing
@testable import MailIndex

@Suite("MailIndex")
struct MailIndexTests {
    @Test func moduleNameIsExported() {
        #expect(MailIndex.moduleName == "MailIndex")
    }
}
