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

        #expect(blob.relativePath.hasPrefix("v2/"))
        #expect(blob.byteCount == data.count)
        #expect(blob.sha256 == AttachmentByteStore.sha256Hex(data))
        #expect(try store.load(relativePath: blob.relativePath) == data)

        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func byteStoreUsesCollisionResistantPathsForNewStores() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let firstData = Data("first attachment".utf8)
        let secondData = Data("second attachment".utf8)

        let firstBlob = try store.store(
            firstData,
            accountId: "account/1",
            messageId: "message:1",
            attachmentId: "attachment?1"
        )
        let secondBlob = try store.store(
            secondData,
            accountId: "account:1",
            messageId: "message/1",
            attachmentId: "attachment/1"
        )

        #expect(firstBlob.relativePath != secondBlob.relativePath)
        #expect(firstBlob.relativePath.split(separator: "/").count == 4)
        #expect(secondBlob.relativePath.split(separator: "/").count == 4)
        #expect(try store.load(relativePath: firstBlob.relativePath) == firstData)
        #expect(try store.load(relativePath: secondBlob.relativePath) == secondData)
    }

    @Test func byteStoreLoadsAndDeletesExistingRelativePaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let relativePath = "account_1/message_1/attachment_1"
        let url = root.appendingPathComponent(relativePath, isDirectory: false)
        let data = Data("legacy attachment".utf8)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)

        #expect(try store.load(relativePath: relativePath) == data)

        try store.delete(relativePath: relativePath)

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
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
