import Foundation
import GRDB
import MailDomain
import Persistence
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

    @Test func serviceFindsBodyMatchesAndReturnsBodySnippets() async throws {
        let service = try makeSearchService()

        let response = try await service.search(try MailSearchQuery(text: "deep tracker"))

        #expect(response.results.map(\.threadID) == ["t-body"])
        #expect(response.results.first?.matchedMessageIDs == ["m-body"])
        #expect(response.results.first?.snippets.contains { $0.field == .body && $0.text.contains("deep launch window tracker") } == true)
    }

    @Test func serviceFindsSubjectSenderAndRecipientMatches() async throws {
        let service = try makeSearchService()

        let subject = try await service.search(try MailSearchQuery(text: "quarterly alpha"))
        let sender = try await service.search(try MailSearchQuery(text: "launch@example.com"))
        let recipient = try await service.search(try MailSearchQuery(text: "recipient@example.com"))

        #expect(subject.results.map(\.threadID) == ["t-subject"])
        #expect(subject.results.first?.snippets.first?.field == .subject)
        #expect(sender.results.first?.threadID == "t-sender")
        #expect(sender.results.first?.sender?.email == "launch@example.com")
        #expect(recipient.results.map(\.threadID) == ["t-recipient"])
        #expect(recipient.results.first?.recipients.map(\.email) == ["recipient@example.com"])
    }

    @Test func serviceAppliesStructuredFilters() async throws {
        let service = try makeSearchService()

        let dateFiltered = try await service.search(try MailSearchQuery(filters: MailSearchFilter(
            dateRange: MailSearchDateRange(
                start: Date(timeIntervalSince1970: 150),
                end: Date(timeIntervalSince1970: 250)
            )
        )))
        let accountFiltered = try await service.search(try MailSearchQuery(
            text: "outlook",
            filters: MailSearchFilter(accountIDs: ["outlook-1"])
        ))
        let mailboxFiltered = try await service.search(try MailSearchQuery(filters: MailSearchFilter(
            canonicalMailboxes: [.sent]
        )))
        let unreadFiltered = try await service.search(try MailSearchQuery(filters: MailSearchFilter(
            isUnread: true
        )))
        let attachmentFiltered = try await service.search(try MailSearchQuery(filters: MailSearchFilter(
            hasAttachment: true
        )))

        #expect(dateFiltered.results.map(\.threadID) == ["t-sender"])
        #expect(accountFiltered.results.map(\.threadID) == ["t-outlook"])
        #expect(mailboxFiltered.results.map(\.threadID) == ["t-sent"])
        #expect(unreadFiltered.results.map(\.threadID) == ["t-unread"])
        #expect(unreadFiltered.results.first?.isUnread == true)
        #expect(attachmentFiltered.results.map(\.threadID) == ["t-attachment"])
        #expect(attachmentFiltered.results.first?.hasAttachments == true)
    }

    @Test func serviceRanksSubjectThenSenderThenBodyForRelevantSearch() async throws {
        let service = try makeSearchService()

        let response = try await service.search(try MailSearchQuery(text: "launch"))

        #expect(Array(response.results.prefix(3).map(\.threadID)) == ["t-subject", "t-sender", "t-body"])
    }

    @Test func serviceReturnsThreadLevelResultsWithStableMetadata() async throws {
        let service = try makeSearchService()

        let response = try await service.search(try MailSearchQuery(text: "threadwide"))
        let result = try #require(response.results.first)

        #expect(response.results.count == 1)
        #expect(result.id == "gmail-1:t-thread")
        #expect(result.threadID == "t-thread")
        #expect(result.accountID == "gmail-1")
        #expect(result.provider == .gmail)
        #expect(result.matchedMessageIDs == ["m-thread-new", "m-thread-old"])
        #expect(result.sentAt == Date(timeIntervalSince1970: 700))
        #expect(result.canonicalMailboxes == [.inbox])
    }

    @Test func serviceReflectsDeletedIndexRows() async throws {
        let db = try makeIndexedSearchDatabase()
        let service = MailSearchService(database: db)

        var before = try await service.search(try MailSearchQuery(text: "removable"))
        #expect(before.results.map(\.threadID) == ["t-delete"])

        _ = try await db.dbQueue.write { database in
            try MessageRecord.deleteOne(database, key: ["account_id": "gmail-1", "id": "m-delete"])
        }

        before = try await service.search(try MailSearchQuery(text: "removable"))
        #expect(before.results.isEmpty)
    }

    @Test func serviceReturnsEmptyResultsForEmptyQueryWithoutFilters() async throws {
        let service = try makeSearchService()

        let response = try await service.search(try MailSearchQuery(text: " "))

        #expect(response.results.isEmpty)
        #expect(response.totalResultCount == 0)
    }

    private func makeSearchService() throws -> MailSearchService {
        MailSearchService(database: try makeIndexedSearchDatabase())
    }

    private func makeIndexedSearchDatabase() throws -> AppDatabase {
        let db = try AppDatabase.openInMemorySync()
        try db.dbQueue.write { database in
            try seedSearchFixture(in: database)
            try LocalSearchIndexPersistence.rebuildAll(in: database, now: 1_000)
        }
        return db
    }

    private func seedSearchFixture(in database: Database) throws {
        try AccountRecord(id: "gmail-1", provider: "gmail", email: "gmail@example.com", createdAt: 1).insert(database)
        try AccountRecord(id: "outlook-1", provider: "outlook", email: "outlook@example.com", createdAt: 1).insert(database)

        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-subject",
            messageID: "m-subject",
            subject: "Launch quarterly alpha plan",
            from: "Planner <planner@example.com>",
            to: "Team <team@example.com>",
            sentAt: 100,
            snippet: "subject snippet",
            bodyText: "ordinary body",
            labels: ["INBOX"]
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-sender",
            messageID: "m-sender",
            subject: "Sender thread",
            from: "Launch Team <launch@example.com>",
            to: "Ops <ops@example.com>",
            sentAt: 200,
            snippet: "sender snippet",
            bodyText: "ordinary body",
            labels: ["INBOX"]
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-body",
            messageID: "m-body",
            subject: "Body thread",
            from: "Ops <ops@example.com>",
            to: "Team <team@example.com>",
            sentAt: 300,
            snippet: "body snippet",
            bodyText: "deep launch window tracker",
            labels: ["INBOX"]
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-recipient",
            messageID: "m-recipient",
            subject: "Recipient thread",
            from: "Ops <ops@example.com>",
            to: "Recipient <recipient@example.com>",
            sentAt: 400,
            snippet: "recipient snippet",
            bodyText: "ordinary body",
            labels: ["INBOX"]
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-sent",
            messageID: "m-sent",
            subject: "Sent thread",
            from: "Me <me@example.com>",
            to: "Team <team@example.com>",
            sentAt: 500,
            snippet: "sent snippet",
            bodyText: "ordinary body",
            labels: ["SENT"],
            flags: MessageRecord.read | MessageRecord.sentByMe
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-unread",
            messageID: "m-unread",
            subject: "Unread thread",
            from: "Ops <ops@example.com>",
            to: "Team <team@example.com>",
            sentAt: 600,
            snippet: "unread snippet",
            bodyText: "ordinary body",
            labels: ["INBOX"],
            flags: 0
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-thread",
            messageID: "m-thread-old",
            subject: "Threadwide old",
            from: "Ops <ops@example.com>",
            to: "Team <team@example.com>",
            sentAt: 650,
            snippet: "threadwide old snippet",
            bodyText: "threadwide older body",
            labels: ["INBOX"],
            flags: MessageRecord.read
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-thread",
            messageID: "m-thread-new",
            subject: "Threadwide new",
            from: "Ops <ops@example.com>",
            to: "Team <team@example.com>",
            sentAt: 700,
            snippet: "threadwide new snippet",
            bodyText: "threadwide newer body",
            labels: ["INBOX"],
            flags: MessageRecord.read,
            insertThread: false
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-attachment",
            messageID: "m-attachment",
            subject: "Attachment thread",
            from: "Ops <ops@example.com>",
            to: "Team <team@example.com>",
            sentAt: 800,
            snippet: "attachment snippet",
            bodyText: "ordinary body",
            labels: ["INBOX"],
            flags: MessageRecord.read,
            attachment: AttachmentRecord(
                id: "att-1",
                messageId: "m-attachment",
                accountId: "gmail-1",
                filename: "invoice.pdf",
                mime: "application/pdf",
                sizeBytes: 42
            )
        )
        try seedMessage(
            in: database,
            accountID: "gmail-1",
            threadID: "t-delete",
            messageID: "m-delete",
            subject: "Removable thread",
            from: "Ops <ops@example.com>",
            to: "Team <team@example.com>",
            sentAt: 900,
            snippet: "removable snippet",
            bodyText: "removable body",
            labels: ["INBOX"],
            flags: MessageRecord.read
        )
        try seedMessage(
            in: database,
            accountID: "outlook-1",
            threadID: "t-outlook",
            messageID: "m-outlook",
            subject: "Outlook local result",
            from: "Outlook <outlook@example.com>",
            to: "Team <team@example.com>",
            sentAt: 1_000,
            snippet: "outlook snippet",
            bodyText: "outlook body",
            labels: ["INBOX"],
            flags: MessageRecord.read
        )
    }

    private func seedMessage(
        in database: Database,
        accountID: String,
        threadID: String,
        messageID: String,
        subject: String,
        from: String,
        to: String,
        sentAt: Int,
        snippet: String,
        bodyText: String,
        labels: [String],
        flags: Int = MessageRecord.read,
        attachment: AttachmentRecord? = nil,
        insertThread: Bool = true
    ) throws {
        if insertThread {
            try ThreadRecord(
                id: threadID,
                accountId: accountID,
                subject: subject,
                snippet: snippet,
                lastMessageAt: sentAt,
                messageCount: 1,
                hasUnread: flags & MessageRecord.read == 0 ? 1 : 0
            ).insert(database)
        }

        try MessageRecord(
            id: messageID,
            threadId: threadID,
            accountId: accountID,
            fromAddr: from,
            toAddr: to,
            sentAt: sentAt,
            snippet: snippet,
            bodyText: bodyText,
            flags: flags
        ).insert(database)

        for label in labels {
            try LabelRecord(id: label, accountId: accountID, name: label, type: .system)
                .insert(database, onConflict: .ignore)
            try ThreadLabelRecord(accountId: accountID, threadId: threadID, labelId: label)
                .insert(database, onConflict: .ignore)
        }

        if let attachment {
            try attachment.insert(database)
        }
    }
}
