import Foundation
import MailDomain
import Testing
@testable import MailIndex

@Suite("MailIndex")
struct MailIndexTests {
    @Test func moduleNameIsExported() {
        #expect(MailIndex.moduleName == "MailIndex")
    }

    @Test func queryConstructionNormalizesTextAndDefaultsToLocalRelevanceSort() throws {
        let query = try MailSearchQuery(text: "  invoice timeline  ")

        #expect(query.text == "invoice timeline")
        #expect(query.mode == .localFullText)
        #expect(query.sort == .relevanceThenNewest)
        #expect(query.limit == 50)
        #expect(query.offset == 0)
    }

    @Test func querySupportsStructuredFilters() throws {
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 200)
        let filter = MailSearchFilter(
            accountIDs: ["account-1"],
            providers: [.gmail, .outlook],
            canonicalMailboxes: [.inbox, .sent],
            from: ["billing@example.com"],
            to: ["ops@example.com"],
            dateRange: MailSearchDateRange(start: start, end: end),
            isUnread: true,
            isSent: false,
            hasAttachment: true,
            attachmentFilenames: ["invoice.pdf"],
            attachmentMIMETypes: ["application/pdf"]
        )

        let query = try MailSearchQuery(
            text: "invoice",
            filters: filter,
            mode: .providerFallbackRequest,
            sort: .newestFirst,
            limit: 25,
            offset: 5
        )

        #expect(query.filters.accountIDs == ["account-1"])
        #expect(query.filters.providers == [.gmail, .outlook])
        #expect(query.filters.canonicalMailboxes == [.inbox, .sent])
        #expect(query.filters.from == ["billing@example.com"])
        #expect(query.filters.to == ["ops@example.com"])
        #expect(query.filters.dateRange == MailSearchDateRange(start: start, end: end))
        #expect(query.filters.isUnread == true)
        #expect(query.filters.isSent == false)
        #expect(query.filters.hasAttachment == true)
        #expect(query.filters.attachmentFilenames == ["invoice.pdf"])
        #expect(query.filters.attachmentMIMETypes == ["application/pdf"])
        #expect(query.mode == .providerFallbackRequest)
        #expect(query.sort == .newestFirst)
        #expect(query.limit == 25)
        #expect(query.offset == 5)
    }

    @Test func emptySearchTextBecomesNilAndPagingIsClamped() throws {
        let query = try MailSearchQuery(text: "  ", limit: 0, offset: -12)

        #expect(query.text == nil)
        #expect(query.limit == 1)
        #expect(query.offset == 0)
    }

    @Test func filterRejectsEmptyValues() {
        #expect(throws: MailSearchValidationError.emptyFilterValue("accountID")) {
            try MailSearchQuery(filters: MailSearchFilter(accountIDs: ["account-1", " "]))
        }

        #expect(throws: MailSearchValidationError.emptyFilterValue("attachmentMIMEType")) {
            try MailSearchQuery(filters: MailSearchFilter(attachmentMIMETypes: [""]))
        }
    }

    @Test func filterRejectsInvalidDateRange() {
        let filter = MailSearchFilter(
            dateRange: MailSearchDateRange(
                start: Date(timeIntervalSince1970: 200),
                end: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(throws: MailSearchValidationError.invalidDateRange) {
            try MailSearchQuery(filters: filter)
        }
    }

    @Test func filterRejectsAttachmentMetadataWhenAttachmentsAreExcluded() {
        let filter = MailSearchFilter(
            hasAttachment: false,
            attachmentFilenames: ["invoice.pdf"]
        )

        #expect(throws: MailSearchValidationError.incompatibleAttachmentFilter) {
            try MailSearchQuery(filters: filter)
        }
    }

    @Test func redactedDescriptionDoesNotExposeQueryOrFilterValues() throws {
        let query = try MailSearchQuery(
            text: "secret acquisition plan",
            filters: MailSearchFilter(
                accountIDs: ["private-account"],
                providers: [.gmail],
                canonicalMailboxes: [.userDefined(id: "customer-label", name: "VIP Customers", kind: .label)],
                from: ["ceo@example.com"],
                to: ["board@example.com"],
                dateRange: MailSearchDateRange(
                    start: Date(timeIntervalSince1970: 100),
                    end: Date(timeIntervalSince1970: 200)
                ),
                isUnread: true,
                isSent: false,
                hasAttachment: true,
                attachmentFilenames: ["secret-plan.pdf"],
                attachmentMIMETypes: ["application/pdf"]
            )
        )

        let description = query.redactedDescription

        #expect(description.contains("<redacted:23 chars>"))
        #expect(description.contains("accounts=1"))
        #expect(description.contains("providers=1"))
        #expect(description.contains("mailboxes=1"))
        #expect(description.contains("from=1"))
        #expect(description.contains("to=1"))
        #expect(description.contains("dateRange=set"))
        #expect(description.contains("attachmentFilenames=1"))
        #expect(!description.contains("secret acquisition plan"))
        #expect(!description.contains("private-account"))
        #expect(!description.contains("ceo@example.com"))
        #expect(!description.contains("board@example.com"))
        #expect(!description.contains("VIP Customers"))
        #expect(!description.contains("secret-plan.pdf"))
    }
}
