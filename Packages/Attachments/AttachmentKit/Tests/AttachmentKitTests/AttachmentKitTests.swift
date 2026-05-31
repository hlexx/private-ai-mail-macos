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

    @Test func byteStoreUsesCollisionResistantPathsForNewStores() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let baselineData = Data("baseline attachment".utf8)
        let accountVariantData = Data("account variant attachment".utf8)
        let messageVariantData = Data("message variant attachment".utf8)
        let attachmentVariantData = Data("attachment variant attachment".utf8)

        let baseline = try store.store(
            baselineData,
            accountId: "account/1",
            messageId: "message:1",
            attachmentId: "attachment?1"
        )
        let repeated = try store.store(
            baselineData,
            accountId: "account/1",
            messageId: "message:1",
            attachmentId: "attachment?1"
        )
        let accountVariant = try store.store(
            accountVariantData,
            accountId: "account:1",
            messageId: "message:1",
            attachmentId: "attachment?1"
        )
        let messageVariant = try store.store(
            messageVariantData,
            accountId: "account/1",
            messageId: "message/1",
            attachmentId: "attachment?1"
        )
        let attachmentVariant = try store.store(
            attachmentVariantData,
            accountId: "account/1",
            messageId: "message:1",
            attachmentId: "attachment/1"
        )

        let uniquePaths = Set([
            baseline.relativePath,
            accountVariant.relativePath,
            messageVariant.relativePath,
            attachmentVariant.relativePath,
        ])
        #expect(repeated.relativePath == baseline.relativePath)
        #expect(uniquePaths.count == 4)
        #expect(uniquePaths.allSatisfy { $0.split(separator: "/").count == 4 })
        #expect(try store.load(relativePath: baseline.relativePath) == baselineData)
        #expect(try store.load(relativePath: accountVariant.relativePath) == accountVariantData)
        #expect(try store.load(relativePath: messageVariant.relativePath) == messageVariantData)
        #expect(try store.load(relativePath: attachmentVariant.relativePath) == attachmentVariantData)
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

    @Test func byteStoreRejectsUnsafeRelativePaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        let outsideFile = outsideRoot.appendingPathComponent("secret.txt")
        try Data("outside attachment bytes".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked-outside", isDirectory: true),
            withDestinationURL: outsideRoot
        )

        let store = AttachmentByteStore(baseURL: root)

        #expect(throws: AttachmentByteStoreError.self) {
            try store.load(relativePath: "/tmp/secret.txt")
        }
        #expect(throws: AttachmentByteStoreError.self) {
            try store.load(relativePath: "../secret.txt")
        }
        #expect(throws: AttachmentByteStoreError.self) {
            try store.load(relativePath: "linked-outside/secret.txt")
        }
        #expect(throws: AttachmentByteStoreError.self) {
            try store.delete(relativePath: "linked-outside/secret.txt")
        }
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
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
