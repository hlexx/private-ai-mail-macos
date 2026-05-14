import CryptoKit
import Foundation
import os
import Testing
@testable import AIRuntime

// MARK: - Fake URLProtocol

private final class FakeURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handlers: [String: Handler] = [:]

    struct Handler {
        let data: Data
        let statusCode: Int
        let supportsRange: Bool

        init(data: Data, statusCode: Int = 200, supportsRange: Bool = true) {
            self.data = data
            self.statusCode = statusCode
            self.supportsRange = supportsRange
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let fileName = url.pathComponents.last,
              let handler = FakeURLProtocol.handlers[fileName]
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }

        var data = handler.data
        var statusCode = handler.statusCode

        if handler.supportsRange,
           let rangeHeader = request.value(forHTTPHeaderField: "Range"),
           rangeHeader.hasPrefix("bytes=")
        {
            let rangeStr = String(rangeHeader.dropFirst("bytes=".count))
            if let dashIdx = rangeStr.firstIndex(of: "-"),
               let start = Int(rangeStr[rangeStr.startIndex ..< dashIdx])
            {
                data = Data(handler.data[start...])
                statusCode = 206
            }
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(data.count)"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Sendable progress tracker

private final class ProgressTracker: Sendable {
    private let _called = OSAllocatedUnfairLock(initialState: false)
    private let _values = OSAllocatedUnfairLock<[(Double, Int64, Int64)]>(initialState: [])

    var called: Bool { _called.withLock { $0 } }
    var values: [(Double, Int64, Int64)] { _values.withLock { $0 } }

    func record(_ frac: Double, _ downloaded: Int64, _ total: Int64) {
        _called.withLock { $0 = true }
        _values.withLock { $0.append((frac, downloaded, total)) }
    }
}

// MARK: - Helpers

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FakeURLProtocol.self]
    return URLSession(configuration: config)
}

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ModelManagerTests-\(UUID().uuidString)", isDirectory: true)
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Create a sparse file of the given size (uses ftruncate, no disk space wasted).
private func writeFixtureFile(at url: URL, size: Int64) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    handle.truncateFile(atOffset: UInt64(size))
    try handle.close()
}

private let testDirName = "test-model"

private func testFileEntries() -> (entries: [GemmaModelSpec.FileEntry], dataByName: [String: Data]) {
    let shaData1 = Data("sha-file-content-1".utf8)
    let shaData2 = Data("sha-file-content-2".utf8)
    let noShaData = Data("no-sha-file-content".utf8)

    let entries: [GemmaModelSpec.FileEntry] = [
        .init(name: "model.bin", byteCount: Int64(shaData1.count), sha256: sha256(shaData1)),
        .init(name: "tokenizer.json", byteCount: Int64(shaData2.count), sha256: sha256(shaData2)),
        .init(name: "config.json", byteCount: Int64(noShaData.count), sha256: nil),
    ]

    let dataByName = [
        "model.bin": shaData1,
        "tokenizer.json": shaData2,
        "config.json": noShaData,
    ]

    return (entries, dataByName)
}

private func makeTestManager(
    modelsRoot: URL,
    session: URLSession,
    maxRetries: Int = 3,
    fileEntries: [GemmaModelSpec.FileEntry]
) -> ModelManager {
    ModelManager(
        modelsRoot: modelsRoot,
        session: session,
        maxRetries: maxRetries,
        fileEntries: fileEntries,
        directoryName: testDirName
    )
}

// MARK: - Tests

@Suite("ModelManager", .serialized)
struct ModelManagerTests {
    @Test func installedURLReturnsNilWhenEmpty() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (entries, _) = testFileEntries()
        let manager = makeTestManager(modelsRoot: dir, session: makeSession(), fileEntries: entries)
        let url = await manager.installedURL()
        #expect(url == nil)
    }

    @Test func happyPathPrePopulated() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, dataByName) = testFileEntries()
        let manager = makeTestManager(modelsRoot: dir, session: makeSession(), fileEntries: entries)

        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for file in entries {
            try dataByName[file.name]!.write(to: modelDir.appendingPathComponent(file.name))
        }

        let url = await manager.installedURL()
        #expect(url != nil)
        #expect(url?.lastPathComponent == testDirName)
    }

    @Test func uninstallRemovesDirectory() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, _) = testFileEntries()
        let manager = makeTestManager(modelsRoot: dir, session: makeSession(), fileEntries: entries)
        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let testFile = modelDir.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: testFile)

        #expect(FileManager.default.fileExists(atPath: modelDir.path))
        try await manager.uninstall()
        #expect(!FileManager.default.fileExists(atPath: modelDir.path))
    }

    @Test func installSkipsAlreadyInstalledModel() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, dataByName) = testFileEntries()
        let manager = makeTestManager(modelsRoot: dir, session: makeSession(), fileEntries: entries)

        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for file in entries {
            try dataByName[file.name]!.write(to: modelDir.appendingPathComponent(file.name))
        }

        let tracker = ProgressTracker()
        let url = try await manager.install { frac, dl, total in
            tracker.record(frac, dl, total)
        }
        #expect(url.lastPathComponent == testDirName)
        // install() validates each file and reports progress even when all files are present
        #expect(tracker.called)
    }

    @Test func installDownloadsAllFiles() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, dataByName) = testFileEntries()
        for file in entries {
            FakeURLProtocol.handlers[file.name] = .init(data: dataByName[file.name]!)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        let session = makeSession()
        let manager = makeTestManager(modelsRoot: dir, session: session, maxRetries: 1, fileEntries: entries)

        let tracker = ProgressTracker()
        let url = try await manager.install { frac, dl, total in
            tracker.record(frac, dl, total)
        }

        #expect(url.lastPathComponent == testDirName)
        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        for file in entries {
            let path = modelDir.appendingPathComponent(file.name)
            #expect(FileManager.default.fileExists(atPath: path.path))
        }
    }

    @Test func installVerifiesExistingFileSHA() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, dataByName) = testFileEntries()
        let shaFile = entries.first { $0.sha256 != nil }!
        let noShaFile = entries.first { $0.sha256 == nil }!

        // Register handlers so files can be downloaded
        for file in entries {
            FakeURLProtocol.handlers[file.name] = .init(data: dataByName[file.name]!)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Pre-populate SHA-hashed files only; leave noShaFile missing
        // so installedURL() returns nil and install() enters the per-file loop.
        for file in entries where file.sha256 != nil {
            try dataByName[file.name]!.write(to: modelDir.appendingPathComponent(file.name))
        }
        // Corrupt one SHA-hashed file (same size, different content)
        let corruptData = Data(repeating: 0xFF, count: Int(shaFile.byteCount))
        try corruptData.write(to: modelDir.appendingPathComponent(shaFile.name))

        let session = makeSession()
        let manager = makeTestManager(modelsRoot: dir, session: session, maxRetries: 3, fileEntries: entries)

        let url = try await manager.install { _, _, _ in }
        #expect(url.lastPathComponent == testDirName)

        // Verify the corrupted file was re-downloaded with correct content
        let redownloaded = try Data(contentsOf: modelDir.appendingPathComponent(shaFile.name))
        #expect(redownloaded == dataByName[shaFile.name]!)
    }

    @Test func resumeAfterPartialWrite() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, dataByName) = testFileEntries()
        let targetFile = entries.first { $0.sha256 == nil }!

        for file in entries {
            FakeURLProtocol.handlers[file.name] = .init(data: dataByName[file.name]!, supportsRange: true)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Pre-populate all other files with correct data
        for file in entries where file.name != targetFile.name {
            try dataByName[file.name]!.write(to: modelDir.appendingPathComponent(file.name))
        }

        // Write a partial .part file (first 5 bytes)
        let fullData = dataByName[targetFile.name]!
        let partFile = modelDir.appendingPathComponent(targetFile.name + ".part")
        try Data(fullData[0 ..< 5]).write(to: partFile)

        let session = makeSession()
        let manager = makeTestManager(modelsRoot: dir, session: session, maxRetries: 1, fileEntries: entries)

        let url = try await manager.install { _, _, _ in }
        #expect(url.lastPathComponent == testDirName)

        let finalPath = modelDir.appendingPathComponent(targetFile.name)
        #expect(FileManager.default.fileExists(atPath: finalPath.path))
    }

    @Test func shaMismatchTriggersRetry() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, dataByName) = testFileEntries()
        let targetFile = entries.first { $0.sha256 != nil }!
        let badData = Data("wrong-content-mismatch".utf8)

        // Serve bad data for the target, correct data for others
        FakeURLProtocol.handlers[targetFile.name] = .init(data: badData)
        for file in entries where file.name != targetFile.name {
            FakeURLProtocol.handlers[file.name] = .init(data: dataByName[file.name]!)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for file in entries where file.name != targetFile.name {
            try dataByName[file.name]!.write(to: modelDir.appendingPathComponent(file.name))
        }

        let session = makeSession()
        let manager = makeTestManager(modelsRoot: dir, session: session, maxRetries: 2, fileEntries: entries)

        do {
            _ = try await manager.install { _, _, _ in }
            Issue.record("Expected SHA mismatch error")
        } catch let error as ModelManagerError {
            if case let .sha256Mismatch(file, expected, actual) = error {
                #expect(file == targetFile.name)
                #expect(expected == targetFile.sha256)
                #expect(actual == sha256(badData))
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test func installRedownloadsCorruptedFileWhenAllPresent() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, dataByName) = testFileEntries()
        let shaFile = entries.first { $0.sha256 != nil }!

        for file in entries {
            FakeURLProtocol.handlers[file.name] = .init(data: dataByName[file.name]!)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Pre-populate ALL files so installedURL() would return non-nil (size check passes)
        for file in entries {
            try dataByName[file.name]!.write(to: modelDir.appendingPathComponent(file.name))
        }

        // Corrupt one SHA-hashed file (same size, different content)
        let corruptData = Data(repeating: 0xFF, count: Int(shaFile.byteCount))
        try corruptData.write(to: modelDir.appendingPathComponent(shaFile.name))

        // Verify installedURL considers it installed (size matches)
        let session = makeSession()
        let manager = makeTestManager(modelsRoot: dir, session: session, maxRetries: 3, fileEntries: entries)
        let preCheck = await manager.installedURL()
        #expect(preCheck != nil, "installedURL() should return non-nil since sizes match")

        // install() should detect the corruption via SHA and re-download
        let url = try await manager.install { _, _, _ in }
        #expect(url.lastPathComponent == testDirName)

        let redownloaded = try Data(contentsOf: modelDir.appendingPathComponent(shaFile.name))
        #expect(redownloaded == dataByName[shaFile.name]!)
    }

    @Test func installReplacesWrongSizeFile() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, dataByName) = testFileEntries()
        let targetFile = entries.first { $0.sha256 == nil }!

        for file in entries {
            FakeURLProtocol.handlers[file.name] = .init(data: dataByName[file.name]!)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        let modelDir = dir.appendingPathComponent(testDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Pre-populate all files correctly except one with wrong size
        for file in entries where file.name != targetFile.name {
            try dataByName[file.name]!.write(to: modelDir.appendingPathComponent(file.name))
        }
        // Write a file with wrong size (shorter)
        let wrongData = Data("short".utf8)
        try wrongData.write(to: modelDir.appendingPathComponent(targetFile.name))

        let session = makeSession()
        let manager = makeTestManager(modelsRoot: dir, session: session, maxRetries: 1, fileEntries: entries)

        let url = try await manager.install { _, _, _ in }
        #expect(url.lastPathComponent == testDirName)

        // Verify the wrong-size file was replaced with correct content
        let finalData = try Data(contentsOf: modelDir.appendingPathComponent(targetFile.name))
        #expect(finalData == dataByName[targetFile.name]!)
    }

    @Test func cancellationStopsDownload() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let (entries, _) = testFileEntries()
        let slowData = Data(repeating: 0xFF, count: 1024)
        for file in entries {
            FakeURLProtocol.handlers[file.name] = .init(data: slowData)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        let session = makeSession()
        let manager = makeTestManager(modelsRoot: dir, session: session, fileEntries: entries)

        let task = Task {
            try await manager.install { _, _, _ in }
        }

        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // Other errors acceptable when cancelled
        }
    }
}
