import Testing
import AppKit
import CoreGraphics
import Foundation
@testable import AttachmentKit

@Suite("AttachmentKit")
struct AttachmentKitTests {
    @Test func localByteStoreStoresReadsAndDeletesAttachmentBytes() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = try LocalAttachmentByteStore(rootURL: rootURL)
        let key = AttachmentByteKey(accountId: "a/1", messageId: "m:1", attachmentId: "../att.pdf")
        let data = Data("invoice bytes".utf8)

        let stored = try store.store(data, for: key)

        #expect(stored.originalByteCount == data.count)
        #expect(stored.storedByteCount == data.count)
        #expect(stored.fileURL.path.hasPrefix(rootURL.path))
        #expect(try store.read(for: key) == data)

        try store.delete(for: key)
        #expect(try store.read(for: key) == nil)
    }

    @Test func localByteStoreDeletesAccountScopedBlobs() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = try LocalAttachmentByteStore(rootURL: rootURL)
        let accountOne = AttachmentByteKey(accountId: "a1", messageId: "m1", attachmentId: "att1")
        let accountTwo = AttachmentByteKey(accountId: "a2", messageId: "m2", attachmentId: "att2")

        try store.store(Data("one".utf8), for: accountOne)
        try store.store(Data("two".utf8), for: accountTwo)
        try store.deleteAccount("a1")

        #expect(try store.read(for: accountOne) == nil)
        #expect(try store.read(for: accountTwo) == Data("two".utf8))
    }

    @Test func localByteStoreExcludesCreatedDirectoriesFromBackup() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = try LocalAttachmentByteStore(rootURL: rootURL)
        let key = AttachmentByteKey(accountId: "a1", messageId: "m1", attachmentId: "att1")
        _ = try store.store(Data("cached".utf8), for: key)

        let rootValues = try rootURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        let messageValues = try store.fileURL(for: key)
            .deletingLastPathComponent()
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(rootValues.isExcludedFromBackup == true)
        #expect(messageValues.isExcludedFromBackup == true)
    }

    @Test func localByteStoreUsesTransformSeamForFutureEncryption() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = try LocalAttachmentByteStore(rootURL: rootURL, transform: PrefixTransform())
        let key = AttachmentByteKey(accountId: "a1", messageId: "m1", attachmentId: "att1")
        let data = Data("plain".utf8)
        let stored = try store.store(data, for: key)

        let rawOnDisk = try Data(contentsOf: stored.fileURL)
        #expect(rawOnDisk != data)
        #expect(String(data: rawOnDisk, encoding: .utf8) == "encoded:a1:plain")
        #expect(try store.read(for: key) == data)
    }

    @Test func platformExtractorExtractsPDFTextWithPageEvidence() throws {
        let extractor = PlatformAttachmentExtractor()
        let data = try makePDFData(pages: ["Invoice 100\nTotal 42", "Payment due Friday"])

        let result = extractor.extract(
            AttachmentExtractionInput(filename: "invoice.pdf", mimeType: "application/pdf", data: data)
        )

        #expect(result.status == .complete)
        #expect(result.extractedText.count == 2)
        #expect(result.extractedText[0].text.contains("Invoice 100"))
        #expect(result.extractedText[0].locator == .page(number: 1))
        #expect(result.extractedText[1].text.contains("Payment due Friday"))
        #expect(result.extractedText[1].locator == .page(number: 2))
        #expect(result.failures.isEmpty)
    }

    @Test func platformExtractorExtractsPlainTextWithByteEvidence() {
        let extractor = PlatformAttachmentExtractor()
        let data = Data("Line one\nLine two".utf8)

        let result = extractor.extract(
            AttachmentExtractionInput(filename: "notes.txt", mimeType: "text/plain", data: data)
        )

        #expect(result.status == .complete)
        #expect(result.combinedText == "Line one\nLine two")
        #expect(result.extractedText.first?.locator == .byteRange(start: 0, end: data.count))
    }

    @Test func platformExtractorConvertsHTMLToPlainTextWithByteEvidence() {
        let extractor = PlatformAttachmentExtractor()
        let html = """
        <html><head><style>.hidden { color: red; }</style><script>ignored()</script></head>
        <body><h1>Invoice</h1><p>Total &amp; tax</p></body></html>
        """
        let data = Data(html.utf8)

        let result = extractor.extract(
            AttachmentExtractionInput(filename: "invoice.html", mimeType: "text/html", data: data)
        )

        #expect(result.status == .complete)
        #expect(result.combinedText.contains("Invoice"))
        #expect(result.combinedText.contains("Total & tax"))
        #expect(!result.combinedText.contains("ignored"))
        #expect(result.extractedText.first?.locator == .byteRange(start: 0, end: data.count))
    }

    @Test func platformExtractorReportsUnsupportedBinaryWithUserFacingReason() {
        let extractor = PlatformAttachmentExtractor()

        let result = extractor.extract(
            AttachmentExtractionInput(
                filename: "archive.bin",
                mimeType: "application/octet-stream",
                data: Data([0, 1, 2, 3])
            )
        )

        #expect(result.status == .unsupported)
        #expect(result.extractedText.isEmpty)
        #expect(result.failures.first?.code == .unsupportedType)
        #expect(result.failures.first?.userFacingReason.isEmpty == false)
        #expect(result.failures.first?.locator == .section(name: "archive.bin"))
    }

    @Test func platformExtractorReturnsIncompleteForEmptyTextAttachment() {
        let extractor = PlatformAttachmentExtractor()

        let result = extractor.extract(
            AttachmentExtractionInput(filename: "empty.txt", mimeType: "text/plain", data: Data("   \n".utf8))
        )

        #expect(result.status == .incomplete)
        #expect(result.extractedText.isEmpty)
        #expect(result.failures.first?.code == .undecodableText)
        #expect(result.failures.first?.locator == .byteRange(start: 0, end: 4))
    }

    @Test func platformExtractorReportsDOCXAsUnsupportedWhenNoParserExists() {
        let extractor = PlatformAttachmentExtractor()

        let result = extractor.extract(
            AttachmentExtractionInput(
                filename: "proposal.docx",
                mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                data: Data("not actually a zip".utf8)
            )
        )

        #expect(result.status == .unsupported)
        #expect(result.failures.first?.code == .unsupportedDocumentFormat)
        #expect(result.failures.first?.technicalReason.contains("No lightweight DOCX parser") == true)
    }

    @Test func platformExtractorFailsForUnreadablePDF() {
        let extractor = PlatformAttachmentExtractor()

        let result = extractor.extract(
            AttachmentExtractionInput(filename: "empty.pdf", mimeType: "application/pdf", data: Data())
        )

        #expect(result.status == .failed)
        #expect(result.extractedText.isEmpty)
        #expect(result.failures.first?.code == .unreadablePDF)
    }

    @Test func platformExtractorReturnsIncompleteWhenImageOCRIsDisabled() {
        let extractor = PlatformAttachmentExtractor()

        let result = extractor.extract(
            AttachmentExtractionInput(filename: "scan.png", mimeType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        )

        #expect(result.status == .incomplete)
        #expect(result.extractedText.isEmpty)
        #expect(result.failures.first?.code == .ocrDisabled)
        #expect(result.failures.first?.userFacingReason.contains("OCR") == true)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePDFData(pages: [String]) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw TestFixtureError.pdfConsumerUnavailable
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw TestFixtureError.pdfContextUnavailable
        }

        for page in pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            page.draw(
                in: CGRect(x: 72, y: 640, width: 468, height: 100),
                withAttributes: [.font: NSFont.systemFont(ofSize: 16)]
            )
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

private struct PrefixTransform: AttachmentByteTransform {
    func encode(_ data: Data, for key: AttachmentByteKey) throws -> Data {
        var encoded = Data("encoded:\(key.accountId):".utf8)
        encoded.append(data)
        return encoded
    }

    func decode(_ data: Data, for key: AttachmentByteKey) throws -> Data {
        let prefix = Data("encoded:\(key.accountId):".utf8)
        guard data.starts(with: prefix) else {
            return data
        }
        return data.dropFirst(prefix.count)
    }
}

private enum TestFixtureError: Error {
    case pdfConsumerUnavailable
    case pdfContextUnavailable
}
