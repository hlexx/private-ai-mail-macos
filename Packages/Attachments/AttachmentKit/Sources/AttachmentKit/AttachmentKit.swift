import AppFoundation
import Foundation

// MARK: - Public API

public struct AttachmentByteKey: Hashable, Sendable {
    public var accountId: String
    public var messageId: String
    public var attachmentId: String

    public init(accountId: String, messageId: String, attachmentId: String) {
        self.accountId = accountId
        self.messageId = messageId
        self.attachmentId = attachmentId
    }
}

public struct StoredAttachmentBytes: Sendable {
    public var key: AttachmentByteKey
    public var fileURL: URL
    public var originalByteCount: Int
    public var storedByteCount: Int

    public init(key: AttachmentByteKey, fileURL: URL, originalByteCount: Int, storedByteCount: Int) {
        self.key = key
        self.fileURL = fileURL
        self.originalByteCount = originalByteCount
        self.storedByteCount = storedByteCount
    }
}

public protocol AttachmentByteTransform: Sendable {
    func encode(_ data: Data, for key: AttachmentByteKey) throws -> Data
    func decode(_ data: Data, for key: AttachmentByteKey) throws -> Data
}

public struct PlainAttachmentByteTransform: AttachmentByteTransform {
    public init() {}

    public func encode(_ data: Data, for key: AttachmentByteKey) throws -> Data {
        data
    }

    public func decode(_ data: Data, for key: AttachmentByteKey) throws -> Data {
        data
    }
}

public protocol AttachmentByteStore: Sendable {
    @discardableResult
    func store(_ data: Data, for key: AttachmentByteKey) throws -> StoredAttachmentBytes
    func read(for key: AttachmentByteKey) throws -> Data?
    func delete(for key: AttachmentByteKey) throws
    func deleteAccount(_ accountId: String) throws
}

public final class LocalAttachmentByteStore: AttachmentByteStore {
    public let rootURL: URL

    private let transform: any AttachmentByteTransform

    public init(
        rootURL: URL,
        transform: any AttachmentByteTransform = PlainAttachmentByteTransform()
    ) throws {
        self.rootURL = rootURL
        self.transform = transform
        try Self.prepareDirectory(rootURL)
    }

    @discardableResult
    public func store(_ data: Data, for key: AttachmentByteKey) throws -> StoredAttachmentBytes {
        let url = fileURL(for: key)
        try Self.prepareDirectory(url.deletingLastPathComponent())
        let storedData = try transform.encode(data, for: key)
        try storedData.write(to: url, options: .atomic)
        return StoredAttachmentBytes(
            key: key,
            fileURL: url,
            originalByteCount: data.count,
            storedByteCount: storedData.count
        )
    }

    public func read(for key: AttachmentByteKey) throws -> Data? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let storedData = try Data(contentsOf: url)
        return try transform.decode(storedData, for: key)
    }

    public func delete(for key: AttachmentByteKey) throws {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    public func deleteAccount(_ accountId: String) throws {
        let url = accountURL(for: accountId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    public func fileURL(for key: AttachmentByteKey) -> URL {
        accountURL(for: key.accountId)
            .appendingPathComponent(Self.pathSegment(for: key.messageId), isDirectory: true)
            .appendingPathComponent(Self.pathSegment(for: key.attachmentId), isDirectory: false)
            .appendingPathExtension("blob")
    }

    private func accountURL(for accountId: String) -> URL {
        rootURL.appendingPathComponent(Self.pathSegment(for: accountId), isDirectory: true)
    }

    private static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excludedURL = url
        try excludedURL.setResourceValues(values)
    }

    private static func pathSegment(for value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
