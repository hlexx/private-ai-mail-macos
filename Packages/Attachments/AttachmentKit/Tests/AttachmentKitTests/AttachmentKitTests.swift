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

    @Test func byteStoreDeletesAllStoredBlobsForAccount() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AttachmentByteStore(baseURL: root)
        let removed = try store.store(
            Data("remove me".utf8),
            accountId: "account/1",
            messageId: "message:1",
            attachmentId: "attachment?1"
        )
        let retained = try store.store(
            Data("keep me".utf8),
            accountId: "account:2",
            messageId: "message:1",
            attachmentId: "attachment?1"
        )

        try store.deleteAccount(accountId: "account/1")

        #expect(try store.fileExists(relativePath: removed.relativePath) == false)
        #expect(try store.load(relativePath: retained.relativePath) == Data("keep me".utf8))
    }

    @Test func byteStoreLoadsAndDeletesExistingRelativePaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyRelativePath = "a_1/m_1/att_1"
        let url = root.appendingPathComponent(legacyRelativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy attachment".utf8).write(to: url)

        let store = AttachmentByteStore(baseURL: root)

        #expect(try store.load(relativePath: legacyRelativePath) == Data("legacy attachment".utf8))
        try store.delete(relativePath: legacyRelativePath)
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
