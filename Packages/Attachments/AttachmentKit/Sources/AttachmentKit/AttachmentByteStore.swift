import CryptoKit
import Foundation

public struct AttachmentStoredBlob: Sendable, Equatable {
    public let relativePath: String
    public let byteCount: Int
    public let sha256: String

    public init(relativePath: String, byteCount: Int, sha256: String) {
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public enum AttachmentByteStoreError: Error, Sendable, Equatable, LocalizedError {
    case unsafeRelativePath(String)
    case sha256Mismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .unsafeRelativePath:
            return "Attachment cache path is invalid."
        case .sha256Mismatch:
            return "Attachment cache checksum does not match stored metadata."
        }
    }
}

public struct AttachmentByteStore: Sendable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public static func defaultBaseURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PrivateAIMail", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    public static func relativePath(accountId: String, messageId: String, attachmentId: String) -> String {
        [
            encodedPathComponent(accountId),
            encodedPathComponent(messageId),
            encodedPathComponent(attachmentId),
        ].joined(separator: "/")
    }

    public func store(
        _ data: Data,
        accountId: String,
        messageId: String,
        attachmentId: String
    ) throws -> AttachmentStoredBlob {
        let relativePath = Self.relativePath(
            accountId: accountId,
            messageId: messageId,
            attachmentId: attachmentId
        )
        let destination = try resolvedURL(for: relativePath)
        let directory = destination.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackupIfNeeded(baseURL)
        try excludeFromBackupIfNeeded(directory)
        try data.write(to: destination, options: [.atomic])

        return AttachmentStoredBlob(
            relativePath: relativePath,
            byteCount: data.count,
            sha256: Self.sha256Hex(data)
        )
    }

    public func load(relativePath: String) throws -> Data {
        try Data(contentsOf: resolvedURL(for: relativePath))
    }

    public func load(relativePath: String, expectedSHA256: String) throws -> Data {
        let data = try load(relativePath: relativePath)
        let actual = Self.sha256Hex(data)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw AttachmentByteStoreError.sha256Mismatch(expected: expectedSHA256, actual: actual)
        }
        return data
    }

    public func delete(relativePath: String) throws {
        let url = try resolvedURL(for: relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func deleteAccount(accountId: String) throws {
        let accountPath = Self.encodedPathComponent(accountId)
        let url = try resolvedURL(for: accountPath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encodedPathComponent(_ raw: String) -> String {
        "v1-" + raw.utf8.map { String(format: "%02x", $0) }.joined()
    }

    private func resolvedURL(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AttachmentByteStoreError.unsafeRelativePath(relativePath)
        }

        let candidate = components.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }
        let basePath = baseURL.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        guard candidatePath == basePath || candidatePath.hasPrefix(basePath + "/") else {
            throw AttachmentByteStoreError.unsafeRelativePath(relativePath)
        }
        return candidate
    }

    private func excludeFromBackupIfNeeded(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }
}
