import Testing
import SwiftUI
import AppKit
@testable import ThreadFeature
import DesignSystem
import Persistence

@Suite("ThreadFeature")
struct ThreadFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ThreadFeature.moduleName == "ThreadFeature")
    }

    // MARK: - MessageRow

    @Test func messageRowExtractsNameFromDisplayFormat() {
        let name = MessageRow.extractName(from: "Marta Kowalski <marta@example.com>")
        #expect(name == "Marta Kowalski")
    }

    @Test func messageRowExtractsNameFromBareEmail() {
        let name = MessageRow.extractName(from: "alex@studio.eu")
        #expect(name == "alex")
    }

    @Test func messageRowExtractsNameFromEmptyString() {
        let name = MessageRow.extractName(from: "")
        #expect(name == "?")
    }

    @Test func messageRowExtractsNameWithQuotes() {
        let name = MessageRow.extractName(from: "\"Jonas R.\" <jonas@example.com>")
        #expect(name == "Jonas R.")
    }

    @Test func messageRowExposesBodyHtml() {
        let record = MessageRecord(
            id: "m1", threadId: "t1", accountId: "a1",
            sentAt: 1_700_000_000,
            bodyHtml: "<p>Hello</p>",
            bodyText: nil
        )
        let row = MessageRow(record: record)
        #expect(row.bodyHtml == "<p>Hello</p>")
        #expect(row.bodyText == "") // falls back to snippet (nil) -> ""
    }

    // MARK: - HTML to Plain Text

    @MainActor @Test func htmlToPlainTextExtractsContent() {
        let html = "<html><body><p>Hello <b>World</b></p><p>Second paragraph</p></body></html>"
        let plain = MessageBodyView.htmlToPlainText(html)
        #expect(plain != nil)
        #expect(plain!.contains("Hello"))
        #expect(plain!.contains("World"))
        #expect(plain!.contains("Second paragraph"))
    }

    @MainActor @Test func htmlToPlainTextStripsExcessiveNewlines() {
        let html = "<p>A</p><br><br><br><br><p>B</p>"
        let plain = MessageBodyView.htmlToPlainText(html)
        #expect(plain != nil)
        // Should not contain 3+ consecutive newlines
        #expect(!plain!.contains("\n\n\n"))
    }

    @MainActor @Test func htmlToPlainTextReturnsNilForEmpty() {
        let result = MessageBodyView.htmlToPlainText("")
        // Empty HTML may return nil or empty string
        #expect(result == nil || result!.isEmpty)
    }

    // MARK: - AttachmentInfo

    @Test func attachmentFormattedSizeKB() {
        let info = AttachmentInfo(id: "a1", filename: "test.pdf", sizeBytes: 284_000, mime: "application/pdf")
        #expect(info.formattedSize == "277 KB")
    }

    @Test func attachmentFormattedSizeMB() {
        let info = AttachmentInfo(id: "a2", filename: "large.zip", sizeBytes: 2_500_000, mime: nil)
        #expect(info.formattedSize == "2.4 MB")
    }

    @Test func attachmentFormattedSizeNil() {
        let info = AttachmentInfo(id: "a3", filename: "unknown", sizeBytes: nil, mime: nil)
        #expect(info.formattedSize == "")
    }
}

// MARK: - Snapshot Tests

@Suite("ThreadView Snapshots")
@MainActor
struct ThreadViewSnapshotTests {

    @MainActor
    @Test func emptyStateDark() {
        let view = emptyStateView()
            .preferredColorScheme(.dark)
            .frame(width: 700, height: 500)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    @MainActor
    @Test func emptyStateLight() {
        let view = emptyStateView()
            .preferredColorScheme(.light)
            .frame(width: 700, height: 500)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    @MainActor
    @Test func messageCardDark() {
        let view = messageCardView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.layout()
    }

    @MainActor
    @Test func messageCardLight() {
        let view = messageCardView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.layout()
    }

    @MainActor
    @Test func attachmentBlockDark() {
        let view = attachmentBlockView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 100)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        host.layout()
    }

    @MainActor
    @Test func attachmentBlockLight() {
        let view = attachmentBlockView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 100)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        host.layout()
    }

    @MainActor
    @Test func headSectionDark() {
        let view = headSectionView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 140)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 140)
        host.layout()
    }

    @MainActor
    @Test func headSectionLight() {
        let view = headSectionView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 140)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 140)
        host.layout()
    }

    private func emptyStateView() -> some View {
        VStack(spacing: 8) {
            Text("Re:")
                .font(.rbSerifItalic(48))
                .foregroundStyle(Color.rbFg3)
            Text("Select a thread")
                .rbTextStyle(.h3)
                .foregroundStyle(Color.rbFg1)
            Text("Re:Box will brief you the moment you open it.")
                .rbTextStyle(.body)
                .foregroundStyle(Color.rbFg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgCanvas)
    }

    private func messageCardView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                AvatarView(name: "Marta Kowalski", size: 28)
                Text("Marta Kowalski")
                    .font(.rbGeist(13, weight: .semibold))
                    .foregroundStyle(Color.rbFg1)
                Spacer()
                Text("Mon 14:30")
                    .font(.rbMono(11))
                    .foregroundStyle(Color.rbFg3)
            }
            Text("Hi — yes, I'll send a clean draft by Friday EOD.")
                .font(.rbGeist(14))
                .foregroundStyle(Color.rbFg2)
                .lineSpacing(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.md)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
        .padding(20)
        .background(Color.rbBgCanvas)
    }

    private func attachmentBlockView() -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: RBRadius.xs)
                .fill(Color.rbBgElev2)
                .frame(width: 38, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("contract.pdf")
                    .font(.rbGeist(13, weight: .medium))
                    .foregroundStyle(Color.rbFg1)
                Text("277 KB · summarized locally")
                    .font(.rbMono(11))
                    .foregroundStyle(Color.rbFg3)
            }
            Spacer()
            Button("Preview") {}
                .buttonStyle(.rbGhost)
            Button("Summarize") {}
                .buttonStyle(.rbSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .padding(20)
        .background(Color.rbBgCanvas)
    }

    @MainActor
    @Test func messageBodyPlainTextDark() {
        let view = MessageBodyView(
            bodyHtml: nil,
            bodyText: "Hi — yes, I'll send a clean draft by Friday EOD.",
            snippet: "Hi",
            attachments: []
        )
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 100)
        .background(Color.rbBgElev1)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        host.layout()
    }

    @MainActor
    @Test func messageBodyHtmlDark() {
        let html = "<p>Hello <b>World</b></p><p>This is an <a href='#'>HTML</a> email.</p>"
        let view = MessageBodyView(
            bodyHtml: html,
            bodyText: nil,
            snippet: "Hello World",
            attachments: []
        )
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 200)
        .background(Color.rbBgElev1)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.layout()
    }

    @MainActor
    @Test func messageBodyWithRemoteImagesPillDark() {
        let html = """
        <p>Newsletter</p>
        <img src="https://example.com/tracker.png" width="1" height="1">
        <p>Click here for deals</p>
        """
        let view = MessageBodyView(
            bodyHtml: html,
            bodyText: nil,
            snippet: "Newsletter",
            attachments: []
        )
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 250)
        .background(Color.rbBgElev1)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 250)
        host.layout()
    }

    @MainActor
    @Test func messageBodySnippetFallbackLight() {
        let view = MessageBodyView(
            bodyHtml: nil,
            bodyText: nil,
            snippet: "Brief preview of the email...",
            attachments: []
        )
        .preferredColorScheme(.light)
        .frame(width: 600, height: 60)
        .background(Color.rbBgElev1)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }

    private func headSectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Re: Contract approval — Acme GmbH")
                .rbTextStyle(.h2)
                .foregroundStyle(Color.rbFg1)
            HStack(spacing: 8) {
                Text("Marta Kowalski").foregroundStyle(Color.rbFg2)
                Text("·").foregroundStyle(Color.rbFg3)
                Text("to alex@studio.eu").foregroundStyle(Color.rbFg2)
                Text("·").foregroundStyle(Color.rbFg3)
                Text("3 messages").foregroundStyle(Color.rbFg2)
            }
            .font(.rbMono(11))
            HStack(spacing: 8) {
                Spacer()
                Button {} label: { Label("Archive", systemImage: "archivebox") }.buttonStyle(.rbGhost)
                Button {} label: { Label("Snooze", systemImage: "clock") }.buttonStyle(.rbGhost)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.rbBgCanvas)
    }

    private func starButtonView(isStarred: Bool) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button {} label: { Label("Archive", systemImage: "archivebox") }.buttonStyle(.rbGhost)
            Button {} label: {
                Label(
                    isStarred ? "Unstar" : "Star",
                    systemImage: isStarred ? "star.fill" : "star"
                )
            }.buttonStyle(.rbGhost)
            Button {} label: { Label("Snooze", systemImage: "clock") }.buttonStyle(.rbGhost)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.rbBgCanvas)
    }

    @MainActor
    @Test func starButtonUnstarredDark() {
        let view = starButtonView(isStarred: false)
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }

    @MainActor
    @Test func starButtonUnstarredLight() {
        let view = starButtonView(isStarred: false)
            .preferredColorScheme(.light)
            .frame(width: 600, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }

    @MainActor
    @Test func starButtonStarredDark() {
        let view = starButtonView(isStarred: true)
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }

    @MainActor
    @Test func starButtonStarredLight() {
        let view = starButtonView(isStarred: true)
            .preferredColorScheme(.light)
            .frame(width: 600, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layout()
    }
}

// MARK: - ThreadStore isStarred Tests

@Suite("ThreadStore Star State")
@MainActor
struct ThreadStoreStarTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.openInMemorySync()
    }

    private func seedThread(db: AppDatabase, starred: Bool) throws {
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO account (id, email, display_name, provider, created_at) VALUES
                ('acc1', 'user@example.com', 'User', 'gmail', 1000)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread) VALUES
                ('t1', 'acc1', 'Test Subject', 'snippet', 1000, 1, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO message (id, thread_id, account_id, from_addr, to_addr, sent_at, flags) VALUES
                ('m1', 't1', 'acc1', 'sender@example.com', 'user@example.com', 1000, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO label (id, account_id, name, type, messages_unread_count, messages_total_count) VALUES
                ('INBOX', 'acc1', 'Inbox', 'system', 0, 0),
                ('STARRED', 'acc1', 'Starred', 'system', 0, 0)
                """)
            try dbConn.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 't1', 'INBOX')
                """)
            if starred {
                try dbConn.execute(sql: """
                    INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                    ('acc1', 't1', 'STARRED')
                    """)
            }
        }
    }

    /// Poll until a condition becomes true, or fail after timeout.
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func isStarredTrueWhenSTARREDLabelPresent() async throws {
        let db = try makeDB()
        try seedThread(db: db, starred: true)
        let store = ThreadStore(db: db)
        store.observe(threadId: "t1", accountId: "acc1")
        try await waitUntil { store.isStarred }
        #expect(store.isStarred == true)
        store.stopObserving()
    }

    @Test func isStarredFalseWhenNoSTARREDLabel() async throws {
        let db = try makeDB()
        try seedThread(db: db, starred: false)
        let store = ThreadStore(db: db)
        store.observe(threadId: "t1", accountId: "acc1")
        // Wait for messages to load (proves observation fired), then assert not starred
        try await waitUntil { !store.messages.isEmpty }
        #expect(store.isStarred == false)
        store.stopObserving()
    }

    @Test func isStarredUpdatesReactivelyOnLabelChange() async throws {
        let db = try makeDB()
        try seedThread(db: db, starred: false)
        let store = ThreadStore(db: db)
        store.observe(threadId: "t1", accountId: "acc1")
        try await waitUntil { !store.messages.isEmpty }
        #expect(store.isStarred == false)

        // Add STARRED label
        try await db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO thread_label (account_id, thread_id, label_id) VALUES
                ('acc1', 't1', 'STARRED')
                """)
        }
        try await waitUntil { store.isStarred }
        #expect(store.isStarred == true)

        // Remove STARRED label
        try await db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                DELETE FROM thread_label WHERE account_id = 'acc1' AND thread_id = 't1' AND label_id = 'STARRED'
                """)
        }
        try await waitUntil { !store.isStarred }
        #expect(store.isStarred == false)

        store.stopObserving()
    }

    @Test func stopObservingResetsIsStarred() async throws {
        let db = try makeDB()
        try seedThread(db: db, starred: true)
        let store = ThreadStore(db: db)
        store.observe(threadId: "t1", accountId: "acc1")
        try await waitUntil { store.isStarred }
        #expect(store.isStarred == true)
        store.stopObserving()
        #expect(store.isStarred == false)
    }
}
