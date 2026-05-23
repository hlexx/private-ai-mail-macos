import AppKit
import AttachmentKit
import Foundation
import ThreadFeature

enum AttachmentPreviewResult: Equatable {
    case opened(URL)
    case missingLocalFile
    case failedToOpen(URL)
}

struct AttachmentPreviewService {
    var byteStore: LocalAttachmentByteStore
    var fileManager: FileManager
    var openLocalFile: @MainActor (URL) -> Bool

    init(
        byteStore: LocalAttachmentByteStore,
        fileManager: FileManager = .default,
        openLocalFile: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.byteStore = byteStore
        self.fileManager = fileManager
        self.openLocalFile = openLocalFile
    }

    @MainActor
    func preview(_ request: AttachmentPreviewRequest) -> AttachmentPreviewResult {
        let key = AttachmentByteKey(
            accountId: request.attachment.accountId,
            messageId: request.attachment.messageId,
            attachmentId: request.attachmentId
        )
        let url = byteStore.fileURL(for: key).standardizedFileURL
        guard url.isFileURL, isInsideByteStore(url) else {
            return .missingLocalFile
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .missingLocalFile
        }

        guard openLocalFile(url) else {
            return .failedToOpen(url)
        }
        return .opened(url)
    }

    private func isInsideByteStore(_ url: URL) -> Bool {
        let rootPath = byteStore.rootURL.standardizedFileURL.path
        let filePath = url.path
        return filePath.hasPrefix(rootPath + "/")
    }
}
