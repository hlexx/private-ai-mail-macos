import Testing
import Foundation
@testable import AttachmentKit

@Suite("AttachmentKit")
struct AttachmentKitTests {
    @Test func moduleNameIsExported() {
        #expect(AttachmentKit.moduleName == "AttachmentKit")
    }

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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
