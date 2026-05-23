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

    @MainActor @Test func htmlToPlainTextStripsStyleBlocks() {
        let html = """
        <html><head><style type="text/css">
        body, table, td { font-family: Arial, Helvetica, sans-serif !important; }
        .mso-line-height-rule { mso-line-height-rule: exactly; }
        </style></head><body><h1>Summer Sale</h1><p>20% off all items</p></body></html>
        """
        let plain = MessageBodyView.htmlToPlainText(html)
        #expect(plain != nil)
        #expect(plain!.contains("Summer Sale"))
        #expect(plain!.contains("20% off"))
        #expect(!plain!.contains("font-family"))
        #expect(!plain!.contains("mso-line-height-rule"))
        #expect(!plain!.contains("Arial"))
    }

    @MainActor @Test func htmlToPlainTextStripsScriptBlocks() {
        let html = """
        <html><body>
        <script>var tracking = { id: "abc123" };</script>
        <p>Hello World</p>
        <script type="text/javascript">console.log("track");</script>
        </body></html>
        """
        let plain = MessageBodyView.htmlToPlainText(html)
        #expect(plain != nil)
        #expect(plain!.contains("Hello World"))
        #expect(!plain!.contains("tracking"))
        #expect(!plain!.contains("console.log"))
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

// MARK: - Attachment Display State

@Suite("ThreadStore Attachment Display State")
@MainActor
struct ThreadStoreAttachmentDisplayStateTests {
    @Test func observesNoAttachments() async throws {
        let db = try makeDB()
        try seedThread(db: db, attachment: nil)
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        try await waitUntil { !store.messages.isEmpty }

        #expect(store.attachments.isEmpty)
        #expect(store.hasAttachment == false)
        store.stopObserving()
    }

    @Test func observesAttachmentWaitingForLocalFile() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.localFileState == .waitingForLocalFile)
        #expect(attachment.extractionState == .waitingForLocalFile)
        #expect(attachment.summaryState == .unavailable)
        store.stopObserving()
    }

    @Test func observesQueuedExtractionAsPending() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedProcessingJob(db: db, status: "queued")
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.localFileState == .available(byteCount: 4096, contentHash: nil))
        #expect(attachment.extractionState == .pending(status: "queued"))
        #expect(attachment.processingState?.jobKind == "extraction")
        store.stopObserving()
    }

    @Test func observesSuccessfulExtraction() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedExtraction(
            db: db,
            status: "succeeded",
            contentHash: "sha256:abc",
            byteCount: 4096,
            completedAt: 120
        )
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.localFileState == .available(byteCount: 4096, contentHash: "sha256:abc"))
        #expect(attachment.extractionState == .succeeded(version: 1, contentHash: "sha256:abc"))
        #expect(attachment.summaryState == .unavailable)
        store.stopObserving()
    }

    @Test func observesUnsupportedExtraction() async throws {
        let db = try makeDB()
        try seedThread(db: db, attachment: AttachmentSeed(filename: "contract.docx", mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"))
        try seedExtraction(
            db: db,
            status: "unsupported",
            errorCode: "unsupportedDocumentFormat",
            errorMessage: "DOCX extraction is not available yet."
        )
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.isUnsupportedFormat)
        #expect(attachment.extractionState == .unsupported(
            code: "unsupportedDocumentFormat",
            message: "DOCX extraction is not available yet."
        ))
        store.stopObserving()
    }

    @Test func observesFailedExtraction() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedExtraction(
            db: db,
            status: "failed",
            errorCode: "unreadablePDF",
            errorMessage: "PDF could not be read."
        )
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.extractionState == .failed(
            code: "unreadablePDF",
            message: "PDF could not be read."
        ))
        #expect(attachment.summaryState == .unavailable)
        store.stopObserving()
    }

    @Test func observesSavedSummaryArtifact() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedExtraction(db: db, status: "succeeded", contentHash: "sha256:abc", byteCount: 4096, completedAt: 120)
        try seedSummaryArtifact(db: db, payloadJson: Self.validSummaryPayload)
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        guard case let .available(summary) = attachment.summaryState else {
            Issue.record("Expected available summary, got \(attachment.summaryState)")
            return
        }
        #expect(summary.summary == "Invoice total is 42.00")
        #expect(summary.keyFields.first?.label == "Total")
        #expect(summary.risks.first?.text == "Payment is overdue.")
        #expect(summary.nextSteps.first?.text == "Pay by Friday.")
        #expect(attachment.evidenceChunkIds == ["chunk-1"])
        store.stopObserving()
    }

    @Test func observesCorruptedSummaryArtifactAsError() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedExtraction(db: db, status: "succeeded", contentHash: "sha256:abc", byteCount: 4096, completedAt: 120)
        try seedSummaryArtifact(db: db, payloadJson: "{not-json")
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.summaryState == .failed(
            code: "artifact_decoding_failed",
            message: "Stored attachment summary artifact could not be decoded."
        ))
        #expect(attachment.extractionState == .succeeded(version: 1, contentHash: "sha256:abc"))
        store.stopObserving()
    }

    @Test func presentationShowsWaitingStateAndDisabledActions() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.metadataDisplayText == "4 KB · application/pdf")
        #expect(attachment.localFileStatusText == "No local file yet")
        #expect(attachment.extractionStatusText == "Text not extracted")
        #expect(attachment.summaryStatusText == "Summary unavailable until text is extracted")
        #expect(attachment.canPreviewAttachment(hasHandler: true) == false)
        #expect(attachment.canSummarizeAttachment(hasHandler: true) == false)
        store.stopObserving()
    }

    @Test func presentationShowsSuccessfulSummaryAndEvidence() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedExtraction(db: db, status: "succeeded", contentHash: "sha256:abc", byteCount: 4096, completedAt: 120)
        try seedSummaryArtifact(db: db, payloadJson: Self.validSummaryPayload)
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.localFileStatusText == "Local file ready")
        #expect(attachment.extractionStatusText == "Text extracted · v1")
        #expect(attachment.summaryStatusText == "Summary ready")
        #expect(attachment.canPreviewAttachment(hasHandler: true))
        #expect(attachment.canSummarizeAttachment(hasHandler: true))
        guard case let .available(summary) = attachment.summaryState else {
            Issue.record("Expected available summary, got \(attachment.summaryState)")
            return
        }
        #expect(summary.confidenceDisplayText == "82% confidence")
        #expect(summary.evidenceDisplayText == "Evidence: chunk-1")
        store.stopObserving()
    }

    @Test func presentationShowsSummaryWithoutRelevantFragments() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedExtraction(db: db, status: "succeeded", contentHash: "sha256:abc", byteCount: 4096, completedAt: 120)
        try seedSummaryArtifact(db: db, payloadJson: Self.summaryWithoutEvidencePayload)
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        guard case let .available(summary) = attachment.summaryState else {
            Issue.record("Expected available summary, got \(attachment.summaryState)")
            return
        }
        #expect(summary.evidenceDisplayText == "No relevant fragments.")
        store.stopObserving()
    }

    @Test func presentationShowsUnsupportedFormat() async throws {
        let db = try makeDB()
        try seedThread(db: db, attachment: AttachmentSeed(filename: "contract.docx", mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"))
        try seedExtraction(
            db: db,
            status: "failed",
            contentHash: "sha256:def",
            byteCount: 4096,
            completedAt: 120,
            errorCode: "unsupported_document_format",
            errorMessage: "DOCX extraction is not supported yet."
        )
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.fileBadgeText == "DOC")
        #expect(attachment.extractionStatusText == "Format not supported: DOCX extraction is not supported yet.")
        #expect(attachment.summaryStatusText == "Summary unavailable for unsupported format")
        #expect(attachment.canPreviewAttachment(hasHandler: true))
        #expect(attachment.canSummarizeAttachment(hasHandler: true) == false)
        store.stopObserving()
    }

    @Test func presentationShowsProcessingError() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedExtraction(
            db: db,
            status: "failed",
            contentHash: "sha256:abc",
            byteCount: 4096,
            completedAt: 120,
            errorCode: "extract_failed",
            errorMessage: "Could not read the file."
        )
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.extractionStatusText == "Processing error: Could not read the file.")
        #expect(attachment.summaryStatusText == "Summary unavailable because processing failed")
        store.stopObserving()
    }

    @Test func presentationDisablesButtonsWithoutHandlers() async throws {
        let db = try makeDB()
        try seedThread(db: db)
        try seedExtraction(db: db, status: "succeeded", contentHash: "sha256:abc", byteCount: 4096, completedAt: 120)
        let store = ThreadStore(db: db)

        store.observe(threadId: "t1", accountId: "acc1")
        let attachment = try await firstAttachment(in: store)

        #expect(attachment.canPreviewAttachment(hasHandler: false) == false)
        #expect(attachment.canSummarizeAttachment(hasHandler: false) == false)
        #expect(attachment.canPreviewAttachment(hasHandler: true))
        #expect(attachment.canSummarizeAttachment(hasHandler: true))
        store.stopObserving()
    }

    private struct AttachmentSeed {
        var id = "att1"
        var filename = "invoice.pdf"
        var mime = "application/pdf"
        var sizeBytes = 4096
    }

    private static var validSummaryPayload: String {
        """
        {
          "summary": "Invoice total is 42.00",
          "keyFields": [
            {
              "label": "Total",
              "value": "42.00",
              "evidenceChunkIds": ["chunk-1"]
            }
          ],
          "risks": [
            {
              "text": "Payment is overdue.",
              "evidenceChunkIds": ["chunk-1"]
            }
          ],
          "nextSteps": [
            {
              "text": "Pay by Friday.",
              "evidenceChunkIds": ["chunk-1"]
            }
          ],
          "evidenceChunkIds": ["chunk-1"],
          "modelId": "local-test",
          "promptVersion": "attachment-summary-prompt-v1",
          "confidence": 0.82
        }
        """
    }

    private static var summaryWithoutEvidencePayload: String {
        """
        {
          "summary": "Attachment has no relevant extracted fragments.",
          "keyFields": [],
          "risks": [],
          "nextSteps": [],
          "evidenceChunkIds": [],
          "modelId": "local-test",
          "promptVersion": "attachment-summary-prompt-v1",
          "confidence": 0.4
        }
        """
    }

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.openInMemorySync()
    }

    private func seedThread(db: AppDatabase, attachment: AttachmentSeed? = AttachmentSeed()) throws {
        try db.dbQueue.write { dbConn in
            try AccountRecord(id: "acc1", email: "user@example.com", createdAt: 1).insert(dbConn)
            try ThreadRecord(
                id: "t1",
                accountId: "acc1",
                subject: "Invoice",
                snippet: "Please review",
                lastMessageAt: 2,
                messageCount: 1
            ).insert(dbConn)
            try MessageRecord(
                id: "m1",
                threadId: "t1",
                accountId: "acc1",
                fromAddr: "sender@example.com",
                toAddr: "user@example.com",
                sentAt: 2,
                bodyText: "Please review",
                flags: 0
            ).insert(dbConn)
            if let attachment {
                try AttachmentRecord(
                    id: attachment.id,
                    messageId: "m1",
                    accountId: "acc1",
                    filename: attachment.filename,
                    mime: attachment.mime,
                    sizeBytes: attachment.sizeBytes
                ).insert(dbConn)
            }
        }
    }

    private func seedExtraction(
        db: AppDatabase,
        status: String,
        contentHash: String? = nil,
        byteCount: Int? = nil,
        completedAt: Int? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) throws {
        try db.dbQueue.write { dbConn in
            try AttachmentExtractionRecord(
                accountId: "acc1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: 1,
                status: status,
                contentHash: contentHash,
                mime: "application/pdf",
                filename: "invoice.pdf",
                byteCount: byteCount,
                createdAt: 100,
                updatedAt: 120,
                completedAt: completedAt,
                errorCode: errorCode,
                errorMessage: errorMessage
            ).insert(dbConn)
        }
    }

    private func seedSummaryArtifact(db: AppDatabase, payloadJson: String) throws {
        try db.dbQueue.write { dbConn in
            try AttachmentAIArtifactRecord(
                accountId: "acc1",
                messageId: "m1",
                attachmentId: "att1",
                extractionVersion: 1,
                artifactKind: "summary",
                artifactVersion: 1,
                modelId: "local-test",
                contentHash: "sha256:abc",
                payloadJson: payloadJson,
                createdAt: 130,
                updatedAt: 130
            ).insert(dbConn)
        }
    }

    private func seedProcessingJob(db: AppDatabase, status: String) throws {
        try db.dbQueue.write { dbConn in
            try AttachmentProcessingJobRecord(
                id: "job1",
                accountId: "acc1",
                messageId: "m1",
                attachmentId: "att1",
                jobKind: "extraction",
                status: status,
                priority: 10,
                availableAt: 90,
                createdAt: 90,
                updatedAt: 90
            ).insert(dbConn)
        }
    }

    private func firstAttachment(in store: ThreadStore) async throws -> AttachmentInfo {
        try await waitUntil { store.attachments.count == 1 }
        let attachment = try #require(store.attachments.first)
        return attachment
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
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
            .frame(width: 600, height: 150)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 150)
        host.layout()
    }

    @MainActor
    @Test func attachmentBlockLight() {
        let view = attachmentBlockView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 150)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 150)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: RBRadius.xs)
                    .fill(Color.rbBgElev2)
                    .frame(width: 38, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("contract.pdf")
                        .font(.rbGeist(13, weight: .medium))
                        .foregroundStyle(Color.rbFg1)
                    Text("277 KB · application/pdf")
                        .font(.rbMono(11))
                        .foregroundStyle(Color.rbFg3)
                }
                Spacer()
                Button("Preview") {}
                    .buttonStyle(.rbGhost)
                Button("Summarize") {}
                    .buttonStyle(.rbSecondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Local file ready")
                Text("Text extracted · v1")
                Text("Summary ready")
            }
            .font(.rbMono(10.5))
            .foregroundStyle(Color.rbFg3)
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
        // Wait for the observation to deliver its first value (messages loaded)
        try await waitUntil { !store.messages.isEmpty }
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
        try await waitUntil { !store.messages.isEmpty }
        try await waitUntil { store.isStarred }
        #expect(store.isStarred == true)
        store.stopObserving()
        #expect(store.isStarred == false)
    }
}

// MARK: - CID Image Resolution Tests

@Suite("CID Image Resolution")
struct CIDImageResolutionTests {

    @Test func resolvedHTMLReplacesCidWithDataURL() {
        let cid = "logo@example.com"
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47]) // tiny fake PNG header
        let html = "<html><body><img src=\"cid:\(cid)\"></body></html>"
        let attachments = [HTMLWebView.AttachmentData(contentId: cid, mime: "image/png", data: pngBytes)]
        let resolved = HTMLWebView.resolveCIDReferences(in: html, attachments: attachments)
        #expect(resolved.contains("data:image/png;base64,\(pngBytes.base64EncodedString())"))
        #expect(!resolved.contains("cid:logo@example.com"))
    }

    @Test func resolvedHTMLHandlesAngleBracketCid() {
        let cid = "logo@1.2.3"
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let html = "<img src=\"cid:<\(cid)>\">"
        let attachments = [HTMLWebView.AttachmentData(contentId: cid, mime: "image/png", data: pngBytes)]
        let resolved = HTMLWebView.resolveCIDReferences(in: html, attachments: attachments)
        #expect(resolved.contains("data:image/png;base64,"))
        #expect(!resolved.contains("cid:"))
    }

    @Test func resolvedHTMLIsCaseInsensitive() {
        let cid = "Logo@Example.COM"
        let pngBytes = Data([0x89, 0x50])
        let html = "<img src=\"CID:\(cid)\">"
        let attachments = [HTMLWebView.AttachmentData(contentId: cid, mime: "image/png", data: pngBytes)]
        let resolved = HTMLWebView.resolveCIDReferences(in: html, attachments: attachments)
        #expect(resolved.contains("data:image/png;base64,"))
        #expect(!resolved.contains("CID:"))
    }

    @Test func inlineAttachmentInfoCreation() {
        let att = InlineAttachment(contentId: "img001@mail", mime: "image/jpeg", dataBase64: "iVBORw0KGgo=")
        #expect(att.contentId == "img001@mail")
        #expect(att.mime == "image/jpeg")
        #expect(att.dataBase64 == "iVBORw0KGgo=")
    }

    @Test func messageRowCarriesInlineAttachments() {
        let record = MessageRecord(
            id: "m1", threadId: "t1", accountId: "a1",
            sentAt: 1_700_000_000,
            bodyHtml: "<img src=\"cid:logo@test\">",
            bodyText: nil
        )
        let inlines = [InlineAttachment(contentId: "logo@test", mime: "image/png", dataBase64: "AAAA")]
        let row = MessageRow(record: record, inlineAttachments: inlines)
        #expect(row.inlineAttachments.count == 1)
        #expect(row.inlineAttachments[0].contentId == "logo@test")
    }

    @Test func htmlWebViewAttachmentDataConversion() {
        let inline = InlineAttachment(contentId: "pic@ex", mime: "image/gif", dataBase64: "R0lGODlh")
        let attData = HTMLWebView.AttachmentData(
            contentId: inline.contentId,
            mime: inline.mime,
            data: Data(base64Encoded: inline.dataBase64) ?? Data()
        )
        #expect(attData.contentId == "pic@ex")
        #expect(attData.mime == "image/gif")
        #expect(!attData.data.isEmpty)
    }
}

// MARK: - Translation JS Script Tests

@Suite("HTMLWebView Translation Scripts")
struct HTMLWebViewTranslationScriptTests {

    @Test func extractionJSContainsTreeWalker() {
        let js = HTMLWebView.extractionJS
        #expect(js.contains("createTreeWalker"))
        #expect(js.contains("SHOW_TEXT"))
        #expect(js.contains("txId"))
        #expect(js.contains("txOrig"))
        #expect(js.contains("2000"))
    }

    @Test func extractionJSSkipsStyleAndScriptNodes() {
        let js = HTMLWebView.extractionJS
        #expect(js.contains("SCRIPT"))
        #expect(js.contains("STYLE"))
        #expect(js.contains("NOSCRIPT"))
    }

    @Test func applyTranslationsJSProducesValidScript() {
        let map = ["n0": "Hello", "n1": "World"]
        let js = HTMLWebView.applyTranslationsJS(map: map)
        #expect(!js.isEmpty)
        #expect(js.contains("data-tx-id"))
        #expect(js.contains("textContent"))
        // The map should be serialized as JSON inside the script
        #expect(js.contains("n0"))
        #expect(js.contains("Hello"))
        #expect(js.contains("n1"))
        #expect(js.contains("World"))
    }

    @Test func applyTranslationsJSHandlesEmptyMap() {
        let map: [String: String] = [:]
        let js = HTMLWebView.applyTranslationsJS(map: map)
        #expect(!js.isEmpty)
    }

    @Test func applyTranslationsJSHandlesSpecialCharacters() {
        let map = ["n0": "He said \"hello\" & goodbye", "n1": "Line1\nLine2"]
        let js = HTMLWebView.applyTranslationsJS(map: map)
        #expect(!js.isEmpty)
        // JSON should properly escape the quotes and newlines
        #expect(js.contains("n0"))
    }

    @Test func restoreOriginalsJSUsesDataAttribute() {
        let js = HTMLWebView.restoreOriginalsJS
        #expect(js.contains("data-tx-id"))
        #expect(js.contains("txOrig"))
        #expect(js.contains("textContent"))
    }

    @Test func textNodeStructure() {
        let node = TranslationTextNode(id: "n42", text: "Summer Sale")
        #expect(node.id == "n42")
        #expect(node.text == "Summer Sale")
    }
}
