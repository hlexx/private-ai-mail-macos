import AttachmentKit
import Foundation
import Testing
import ThreadFeature

@testable import PrivateAIMail

@Suite("AttachmentPreviewService")
struct AttachmentPreviewServiceTests {
    @MainActor
    @Test func opensExistingLocalAttachmentFile() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let byteStore = try LocalAttachmentByteStore(rootURL: rootURL)
        let key = AttachmentByteKey(accountId: "acc1", messageId: "m1", attachmentId: "att1")
        let stored = try byteStore.store(Data("local attachment".utf8), for: key)
        var openedURL: URL?
        let service = AttachmentPreviewService(byteStore: byteStore) { url in
            openedURL = url
            return true
        }
        let request = AttachmentPreviewRequest(attachment: attachmentInfo())

        let result = service.preview(request)

        #expect(result == .opened(stored.fileURL.standardizedFileURL))
        #expect(openedURL == stored.fileURL.standardizedFileURL)
    }

    @MainActor
    @Test func reportsMissingLocalAttachmentFileWithoutOpening() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let byteStore = try LocalAttachmentByteStore(rootURL: rootURL)
        var didOpen = false
        let service = AttachmentPreviewService(byteStore: byteStore) { _ in
            didOpen = true
            return true
        }
        let request = AttachmentPreviewRequest(attachment: attachmentInfo())

        let result = service.preview(request)

        #expect(result == .missingLocalFile)
        #expect(didOpen == false)
    }

    @MainActor
    @Test func reportsOpenFailureForExistingFile() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let byteStore = try LocalAttachmentByteStore(rootURL: rootURL)
        let key = AttachmentByteKey(accountId: "acc1", messageId: "m1", attachmentId: "att1")
        let stored = try byteStore.store(Data("local attachment".utf8), for: key)
        let service = AttachmentPreviewService(byteStore: byteStore) { _ in
            false
        }
        let request = AttachmentPreviewRequest(attachment: attachmentInfo())

        let result = service.preview(request)

        #expect(result == .failedToOpen(stored.fileURL.standardizedFileURL))
    }

    private func attachmentInfo() -> AttachmentInfo {
        AttachmentInfo(
            id: "att1",
            accountId: "acc1",
            messageId: "m1",
            filename: "invoice.pdf",
            sizeBytes: 4096,
            mime: "application/pdf"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAppAttachmentPreview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }
}
