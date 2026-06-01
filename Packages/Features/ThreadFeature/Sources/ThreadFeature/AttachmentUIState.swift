import AttachmentKit
import Foundation

public enum AttachmentCacheState: Sendable, Equatable {
    case metadataOnly
    case downloading
    case cached
    case failed(String)
    case deleted
}

public enum AttachmentPreviewAvailability: Sendable, Equatable {
    case unavailable
    case previewAvailable(URL)
    case unsupportedPreview(String)
}

public struct AttachmentUIState: Sendable, Equatable {
    public let cacheState: AttachmentCacheState
    public let previewAvailability: AttachmentPreviewAvailability

    public init(cacheState: AttachmentCacheState, previewAvailability: AttachmentPreviewAvailability = .unavailable) {
        self.cacheState = cacheState
        self.previewAvailability = previewAvailability
    }

    public static let metadataOnly = AttachmentUIState(cacheState: .metadataOnly)
    public static let downloading = AttachmentUIState(cacheState: .downloading)
    public static let cached = AttachmentUIState(cacheState: .cached)
    public static let deleted = AttachmentUIState(cacheState: .deleted)

    public static func previewAvailable(_ url: URL) -> AttachmentUIState {
        AttachmentUIState(cacheState: .cached, previewAvailability: .previewAvailable(url))
    }

    public static func unsupportedPreview(_ reason: String) -> AttachmentUIState {
        AttachmentUIState(cacheState: .cached, previewAvailability: .unsupportedPreview(reason))
    }

    public static func failed(_ message: String) -> AttachmentUIState {
        AttachmentUIState(cacheState: .failed(message))
    }

    public var previewURL: URL? {
        guard case .previewAvailable(let url) = previewAvailability else { return nil }
        return url
    }

    public var statusText: String {
        switch cacheState {
        case .metadataOnly:
            return "metadata only"
        case .downloading:
            return "downloading"
        case .cached:
            switch previewAvailability {
            case .unavailable:
                return "cached locally"
            case .previewAvailable:
                return "preview available"
            case .unsupportedPreview:
                return "preview unsupported"
            }
        case .failed:
            return "attachment failed"
        case .deleted:
            return "cached file deleted"
        }
    }

    public var detailText: String? {
        switch cacheState {
        case .metadataOnly, .downloading, .cached:
            if case .unsupportedPreview(let reason) = previewAvailability {
                return reason
            }
            return nil
        case .failed(let message):
            return message
        case .deleted:
            return "The cached attachment file was deleted. Summarize again to fetch a fresh local copy."
        }
    }
}

public struct AttachmentUIStateResolver: Sendable {
    public let byteStore: AttachmentByteStore

    public init(byteStore: AttachmentByteStore = AttachmentByteStore(baseURL: AttachmentByteStore.defaultBaseURL())) {
        self.byteStore = byteStore
    }

    public func state(for attachment: AttachmentInfo) -> AttachmentUIState {
        guard let cache = attachment.cache else {
            return .metadataOnly
        }

        do {
            guard try byteStore.fileExists(relativePath: cache.relativePath) else {
                return .deleted
            }
            let url = try byteStore.fileURL(relativePath: cache.relativePath)
            switch Self.previewSupport(mime: attachment.mime, filename: attachment.filename) {
            case .supported:
                return .previewAvailable(url)
            case .unknown:
                return .cached
            case .unsupported(let reason):
                return .unsupportedPreview(reason)
            }
        } catch {
            return .failed("Attachment cache metadata is invalid.")
        }
    }

    static func previewSupport(mime: String?, filename: String) -> PreviewSupport {
        let normalizedMime = mime?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let fileExtension = (filename as NSString).pathExtension.lowercased()

        if normalizedMime == nil && fileExtension.isEmpty {
            return .unknown
        }

        if let normalizedMime, supportedPreviewMIMEs.contains(normalizedMime) {
            return .supported
        }
        if let normalizedMime, normalizedMime.hasPrefix("image/") || normalizedMime.hasPrefix("text/") {
            return .supported
        }
        if supportedPreviewExtensions.contains(fileExtension) {
            return .supported
        }

        return .unsupported("Preview is not available for this attachment type.")
    }

    enum PreviewSupport: Equatable {
        case supported
        case unknown
        case unsupported(String)
    }

    private static let supportedPreviewMIMEs: Set<String> = [
        "application/csv",
        "application/json",
        "application/pdf",
        "application/rtf",
        "application/xml",
        "text/csv",
        "text/markdown",
        "text/plain",
        "text/rtf",
        "text/xml",
    ]

    private static let supportedPreviewExtensions: Set<String> = [
        "csv",
        "gif",
        "heic",
        "jpeg",
        "jpg",
        "json",
        "md",
        "pdf",
        "png",
        "rtf",
        "text",
        "tif",
        "tiff",
        "txt",
        "xml",
    ]
}
