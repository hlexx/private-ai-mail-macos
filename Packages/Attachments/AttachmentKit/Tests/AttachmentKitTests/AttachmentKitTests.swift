import Testing
import Foundation
@testable import AttachmentKit

@Suite("AttachmentKit")
struct AttachmentKitTests {
    @Test func moduleNameIsExported() {
        #expect(AttachmentKit.moduleName == "AttachmentKit")
    }

    @Test func byteStoreRoundTripsDataAndExcludesBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let data = Data("hello attachment".utf8)
        let blob = try store.store(data, accountId: "a/1", messageId: "m:1", attachmentId: "att?1")

        #expect(blob.byteCount == data.count)
        #expect(blob.sha256 == AttachmentByteStore.sha256Hex(data))
        #expect(try store.load(relativePath: blob.relativePath) == data)

        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func textExtractorReadsUTF8Text() {
        let result = AttachmentTextExtractor.extract(
            data: Data("Amount due: EUR 1840".utf8),
            mime: "text/plain",
            filename: "invoice.txt"
        )

        #expect(result.status == .extracted)
        #expect(result.text?.contains("EUR 1840") == true)
    }

    @Test func textExtractorRejectsUnsupportedTypes() {
        let result = AttachmentTextExtractor.extract(
            data: Data([0x00, 0x01]),
            mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            filename: "contract.docx"
        )

        #expect(result.status == .unsupported)
        #expect(result.unsupportedReason?.contains("Unsupported") == true)
    }
}
