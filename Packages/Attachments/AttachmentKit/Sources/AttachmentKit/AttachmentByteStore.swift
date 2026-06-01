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

public enum AttachmentByteStoreError: Error, Sendable, Equatable {
    case invalidRelativePath(String)
    case relativePathEscapesStore(String)
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

    public func store(
        _ data: Data,
        accountId: String,
        messageId: String,
        attachmentId: String
    ) throws -> AttachmentStoredBlob {
        let relativePath = [
            "v2",
            Self.identifierPathComponent(accountId),
            Self.identifierPathComponent(messageId),
            Self.identifierPathComponent(attachmentId),
        ].joined(separator: "/")
        let destination = try fileURL(for: relativePath)
        let directory = destination.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackupIfNeeded(baseURL)
        try data.write(to: destination, options: [.atomic])

        return AttachmentStoredBlob(
            relativePath: relativePath,
            byteCount: data.count,
            sha256: Self.sha256Hex(data)
        )
    }

    public func load(relativePath: String) throws -> Data {
        try Data(contentsOf: fileURL(for: relativePath))
    }

    public func delete(relativePath: String) throws {
        let url = try fileURL(for: relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func deleteAccount(accountId: String) throws {
        let relativePath = [
            "v2",
            Self.identifierPathComponent(accountId),
        ].joined(separator: "/")
        let url = try fileURL(for: relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func fileExists(relativePath: String) throws -> Bool {
        let url = try fileURL(for: relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func fileURL(relativePath: String) throws -> URL {
        try fileURL(for: relativePath)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func identifierPathComponent(_ raw: String) -> String {
        sha256Hex(Data(raw.utf8))
    }

    private func fileURL(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relativePath.hasPrefix("/"),
              !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw AttachmentByteStoreError.invalidRelativePath(relativePath)
        }

        let resolvedBase = baseURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = components.reduce(resolvedBase) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let basePath = resolvedBase.path
        let candidatePath = resolvedCandidate.path

        guard candidatePath == basePath || candidatePath.hasPrefix(basePath + "/") else {
            throw AttachmentByteStoreError.relativePathEscapesStore(relativePath)
        }
        return resolvedCandidate
    }

    private func excludeFromBackupIfNeeded(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }
}
