import Testing
@testable import MailSync

@Suite("MailSync")
struct MailSyncTests {
    @Test func moduleNameIsExported() {
        #expect(MailSync.moduleName == "MailSync")
    }
}
