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

// MARK: - Tests

@Suite("ModelManager", .serialized)
struct ModelManagerTests {
    @Test func installedURLReturnsNilWhenEmpty() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = ModelManager(modelsRoot: dir, session: makeSession())
        let url = await manager.installedURL()
        #expect(url == nil)
    }

    @Test func happyPathPrePopulated() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fixtureData = Data(repeating: 0xAB, count: 1024)

        let manager = ModelManager(modelsRoot: dir, session: makeSession())

        // Pre-populate the model directory to simulate a completed install
        let modelDir = dir.appendingPathComponent(GemmaModelSpec.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for file in GemmaModelSpec.files {
            try fixtureData.write(to: modelDir.appendingPathComponent(file.name))
        }

        let url = await manager.installedURL()
        #expect(url != nil)
        #expect(url?.lastPathComponent == GemmaModelSpec.directoryName)
    }

    @Test func uninstallRemovesDirectory() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = ModelManager(modelsRoot: dir, session: makeSession())
        let modelDir = dir.appendingPathComponent(GemmaModelSpec.directoryName, isDirectory: true)
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

        let manager = ModelManager(modelsRoot: dir, session: makeSession())

        // Pre-populate all files
        let modelDir = dir.appendingPathComponent(GemmaModelSpec.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for file in GemmaModelSpec.files {
            try Data("x".utf8).write(to: modelDir.appendingPathComponent(file.name))
        }

        let tracker = ProgressTracker()
        let url = try await manager.install { frac, dl, total in
            tracker.record(frac, dl, total)
        }
        #expect(url.lastPathComponent == GemmaModelSpec.directoryName)
        // Progress should NOT be called because install returns immediately
        #expect(!tracker.called)
    }

    @Test func installDownloadsFilesWithoutSHA() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let smallContent = Data("test-content".utf8)

        for file in GemmaModelSpec.files {
            FakeURLProtocol.handlers[file.name] = .init(data: smallContent)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        // Pre-populate files WITH sha256 so only files without sha256 need downloading
        let modelDir = dir.appendingPathComponent(GemmaModelSpec.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for file in GemmaModelSpec.files where file.sha256 != nil {
            try smallContent.write(to: modelDir.appendingPathComponent(file.name))
        }

        let session = makeSession()
        let manager = ModelManager(modelsRoot: dir, session: session, maxRetries: 1)

        let tracker = ProgressTracker()
        let url = try await manager.install { frac, dl, total in
            tracker.record(frac, dl, total)
        }

        #expect(url.lastPathComponent == GemmaModelSpec.directoryName)
        for file in GemmaModelSpec.files where file.sha256 == nil {
            let path = modelDir.appendingPathComponent(file.name)
            #expect(FileManager.default.fileExists(atPath: path.path))
        }
    }

    @Test func resumeAfterPartialWrite() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fullData = Data(repeating: 0xCD, count: 100)

        let targetFile = GemmaModelSpec.files.first { $0.sha256 == nil }!
        FakeURLProtocol.handlers[targetFile.name] = .init(data: fullData, supportsRange: true)
        defer { FakeURLProtocol.handlers.removeAll() }

        // Pre-populate all other files
        let modelDir = dir.appendingPathComponent(GemmaModelSpec.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for file in GemmaModelSpec.files where file.name != targetFile.name {
            try Data("ok".utf8).write(to: modelDir.appendingPathComponent(file.name))
        }

        // Write a partial .part file (first 40 bytes)
        let partFile = modelDir.appendingPathComponent(targetFile.name + ".part")
        try Data(fullData[0 ..< 40]).write(to: partFile)

        let session = makeSession()
        let manager = ModelManager(modelsRoot: dir, session: session, maxRetries: 1)

        let url = try await manager.install { _, _, _ in }
        #expect(url.lastPathComponent == GemmaModelSpec.directoryName)

        let finalPath = modelDir.appendingPathComponent(targetFile.name)
        #expect(FileManager.default.fileExists(atPath: finalPath.path))
    }

    @Test func shaMismatchTriggersRetry() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let badData = Data("wrong-content".utf8)

        let targetFile = GemmaModelSpec.files.first { $0.sha256 != nil }!
        FakeURLProtocol.handlers[targetFile.name] = .init(data: badData)
        defer { FakeURLProtocol.handlers.removeAll() }

        // Pre-populate all other files
        let modelDir = dir.appendingPathComponent(GemmaModelSpec.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for file in GemmaModelSpec.files where file.name != targetFile.name {
            try Data("ok".utf8).write(to: modelDir.appendingPathComponent(file.name))
        }

        let session = makeSession()
        let manager = ModelManager(modelsRoot: dir, session: session, maxRetries: 2)

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

    @Test func cancellationStopsDownload() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let slowData = Data(repeating: 0xFF, count: 1024)
        for file in GemmaModelSpec.files {
            FakeURLProtocol.handlers[file.name] = .init(data: slowData)
        }
        defer { FakeURLProtocol.handlers.removeAll() }

        let session = makeSession()
        let manager = ModelManager(modelsRoot: dir, session: session)

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
