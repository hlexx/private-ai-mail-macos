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
        #expect(blob.relativePath == AttachmentByteStore.relativePath(
            accountId: "a/1",
            messageId: "m:1",
            attachmentId: "att?1"
        ))
        #expect(try store.load(relativePath: blob.relativePath) == data)
        #expect(try store.load(relativePath: blob.relativePath, expectedSHA256: blob.sha256) == data)
        #expect(try store.fileExists(relativePath: blob.relativePath))
        #expect(try store.fileURL(relativePath: blob.relativePath).path.hasPrefix(root.path))

        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func byteStoreKeepsDistinctProviderIdsFromColliding() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let first = try store.store(
            Data("first".utf8),
            accountId: "a/1",
            messageId: "m:1",
            attachmentId: "att?1"
        )
        let second = try store.store(
            Data("second".utf8),
            accountId: "a_1",
            messageId: "m_1",
            attachmentId: "att_1"
        )

        #expect(first.relativePath != second.relativePath)
        #expect(try store.load(relativePath: first.relativePath) == Data("first".utf8))
        #expect(try store.load(relativePath: second.relativePath) == Data("second".utf8))
    }

    @Test func byteStoreRejectsTraversalPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)

        do {
            _ = try store.load(relativePath: "../outside")
            Issue.record("Expected traversal load to fail")
        } catch AttachmentByteStoreError.unsafeRelativePath(let path) {
            #expect(path == "../outside")
        }

        do {
            try store.delete(relativePath: "/absolute")
            Issue.record("Expected absolute delete to fail")
        } catch AttachmentByteStoreError.unsafeRelativePath(let path) {
            #expect(path == "/absolute")
        }
    }

    @Test func byteStoreDuplicateStoreIsDeterministic() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let data = Data("stable".utf8)
        let first = try store.store(data, accountId: "a1", messageId: "m1", attachmentId: "att1")
        let second = try store.store(data, accountId: "a1", messageId: "m1", attachmentId: "att1")

        #expect(first == second)
        #expect(try store.load(relativePath: first.relativePath) == data)
    }

    @Test func byteStoreDetectsSHA256Mismatch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let blob = try store.store(Data("original".utf8), accountId: "a1", messageId: "m1", attachmentId: "att1")
        try Data("tampered".utf8).write(to: root.appendingPathComponent(blob.relativePath), options: [.atomic])

        do {
            _ = try store.load(relativePath: blob.relativePath, expectedSHA256: blob.sha256)
            Issue.record("Expected checksum mismatch")
        } catch AttachmentByteStoreError.sha256Mismatch(let expected, let actual) {
            #expect(expected == blob.sha256)
            #expect(actual == AttachmentByteStore.sha256Hex(Data("tampered".utf8)))
        }
    }

    @Test func byteStoreDeletesSingleAccountCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let deletedBlob = try store.store(
            Data("delete me".utf8),
            accountId: "account/a",
            messageId: "m1",
            attachmentId: "att1"
        )
        let survivingBlob = try store.store(
            Data("keep me".utf8),
            accountId: "account/b",
            messageId: "m1",
            attachmentId: "att1"
        )

        try store.deleteAccount(accountId: "account/a")

        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(deletedBlob.relativePath).path))
        #expect(try store.load(relativePath: survivingBlob.relativePath) == Data("keep me".utf8))
    }

    @Test func byteStoreDeletesIndividualBlob() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let blob = try store.store(Data("delete one".utf8), accountId: "a1", messageId: "m1", attachmentId: "att1")

        try store.delete(relativePath: blob.relativePath)

        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(blob.relativePath).path))
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

    @Test func textExtractorRejectsImageOCR() {
        let result = AttachmentTextExtractor.extract(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            mime: "image/png",
            filename: "scan.png"
        )

        #expect(result.status == .unsupported)
        #expect(result.text == nil)
        #expect(result.unsupportedReason?.contains("Unsupported") == true)
    }
}
