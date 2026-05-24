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
            Self.safePathComponent(accountId),
            Self.safePathComponent(messageId),
            Self.safePathComponent(attachmentId),
        ].joined(separator: "/")
        let destination = baseURL.appendingPathComponent(relativePath, isDirectory: false)
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
        try Data(contentsOf: baseURL.appendingPathComponent(relativePath, isDirectory: false))
    }

    public func delete(relativePath: String) throws {
        let url = baseURL.appendingPathComponent(relativePath, isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        let result = String(scalars)
        return result.isEmpty ? "_" : result
    }

    private func excludeFromBackupIfNeeded(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
    }
}
