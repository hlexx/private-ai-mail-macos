import CryptoKit
import Foundation

public actor ModelManager {
    private let modelsRoot: URL
    private let session: URLSession
    private let maxRetries: Int
    let fileEntries: [GemmaModelSpec.FileEntry]
    let directoryName: String

    public init(
        modelsRoot: URL? = nil,
        session: URLSession = .shared,
        maxRetries: Int = 3
    ) {
        if let modelsRoot {
            self.modelsRoot = modelsRoot
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            self.modelsRoot = appSupport
                .appendingPathComponent("PrivateAIMail", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
        }
        self.session = session
        self.maxRetries = maxRetries
        self.fileEntries = GemmaModelSpec.files
        self.directoryName = GemmaModelSpec.directoryName
    }

    init(
        modelsRoot: URL,
        session: URLSession,
        maxRetries: Int = 3,
        fileEntries: [GemmaModelSpec.FileEntry],
        directoryName: String
    ) {
        self.modelsRoot = modelsRoot
        self.session = session
        self.maxRetries = maxRetries
        self.fileEntries = fileEntries
        self.directoryName = directoryName
    }

    private var modelDirectory: URL {
        modelsRoot.appendingPathComponent(directoryName, isDirectory: true)
    }

    // MARK: - Public API

    public func installedURL() -> URL? {
        let dir = modelDirectory
        let fm = FileManager.default
        for file in fileEntries {
            let path = dir.appendingPathComponent(file.name)
            guard fm.fileExists(atPath: path.path),
                  let attrs = try? fm.attributesOfItem(atPath: path.path),
                  let size = attrs[.size] as? Int64,
                  size == file.byteCount
            else { return nil }
        }
        return dir
    }

    @discardableResult
    public func install(
        progress: @Sendable @escaping (Double, Int64, Int64) -> Void
    ) async throws -> URL {
        let dir = modelDirectory
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let totalBytes = fileEntries.reduce(Int64(0)) { $0 + $1.byteCount }
        var downloadedSoFar: Int64 = 0

        for file in fileEntries {
            try Task.checkCancellation()

            let dest = dir.appendingPathComponent(file.name)
            if fm.fileExists(atPath: dest.path),
               let attrs = try? fm.attributesOfItem(atPath: dest.path),
               let size = attrs[.size] as? Int64,
               size == file.byteCount {
                if let expectedHash = file.sha256 {
                    let actual = try sha256Hash(of: dest)
                    if actual != expectedHash {
                        try? fm.removeItem(at: dest)
                    } else {
                        downloadedSoFar += file.byteCount
                        progress(Double(downloadedSoFar) / Double(totalBytes), downloadedSoFar, totalBytes)
                        continue
                    }
                } else {
                    downloadedSoFar += file.byteCount
                    progress(Double(downloadedSoFar) / Double(totalBytes), downloadedSoFar, totalBytes)
                    continue
                }
            }

            let partFile = dir.appendingPathComponent(file.name + ".part")
            let existingBytes = partFileSize(partFile)
            var bytesForThisFile = existingBytes

            var lastError: (any Error)?
            for attempt in 0 ..< maxRetries {
                bytesForThisFile = partFileSize(partFile)
                do {
                    try Task.checkCancellation()
                    let baseOffset = downloadedSoFar
                    bytesForThisFile = try await downloadFile(
                        file: file,
                        to: partFile,
                        resumeFrom: bytesForThisFile,
                        onProgress: { downloaded in
                            let current = baseOffset + downloaded
                            progress(Double(current) / Double(totalBytes), current, totalBytes)
                        }
                    )

                    if let expectedHash = file.sha256 {
                        let actual = try sha256Hash(of: partFile)
                        if actual != expectedHash {
                            try? fm.removeItem(at: partFile)
                            bytesForThisFile = 0
                            throw ModelManagerError.sha256Mismatch(
                                file: file.name, expected: expectedHash, actual: actual
                            )
                        }
                    }

                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.moveItem(at: partFile, to: dest)
                    lastError = nil
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                    if attempt < maxRetries - 1 {
                        continue
                    }
                }
            }

            if let lastError {
                throw lastError
            }

            downloadedSoFar += file.byteCount
            progress(Double(downloadedSoFar) / Double(totalBytes), downloadedSoFar, totalBytes)
        }

        return dir
    }

    public func uninstall() throws {
        let fm = FileManager.default
        let dir = modelDirectory
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
    }

    // MARK: - Private

    private func downloadFile(
        file: GemmaModelSpec.FileEntry,
        to partFile: URL,
        resumeFrom existingBytes: Int64,
        onProgress: @Sendable @escaping (Int64) -> Void
    ) async throws -> Int64 {
        let url = GemmaModelSpec.downloadURL(for: file.name)
        var request = URLRequest(url: url)

        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }

        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelManagerError.invalidResponse(file: file.name)
        }

        let acceptableStatuses: Set<Int> = [200, 206]
        guard acceptableStatuses.contains(httpResponse.statusCode) else {
            throw ModelManagerError.httpError(
                file: file.name, statusCode: httpResponse.statusCode
            )
        }

        let shouldAppend = httpResponse.statusCode == 206 && existingBytes > 0
        let handle: FileHandle
        if shouldAppend, FileManager.default.fileExists(atPath: partFile.path) {
            handle = try FileHandle(forWritingTo: partFile)
            handle.seekToEndOfFile()
        } else {
            FileManager.default.createFile(atPath: partFile.path, contents: nil)
            handle = try FileHandle(forWritingTo: partFile)
        }

        defer { try? handle.close() }

        var written: Int64 = shouldAppend ? existingBytes : 0
        let bufferSize = 256 * 1024
        var buffer = Data()
        buffer.reserveCapacity(bufferSize)

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= bufferSize {
                handle.write(buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                onProgress(written)
            }
        }

        if !buffer.isEmpty {
            handle.write(buffer)
            written += Int64(buffer.count)
            onProgress(written)
        }

        return written
    }

    private func partFileSize(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64
        else { return 0 }
        return size
    }

    private func sha256Hash(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum ModelManagerError: Error, Sendable {
    case sha256Mismatch(file: String, expected: String, actual: String)
    case invalidResponse(file: String)
    case httpError(file: String, statusCode: Int)
}
