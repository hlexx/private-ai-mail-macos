import Foundation

extension AttachmentInfo {
    var fileBadgeText: String {
        guard let mime = mime?.lowercased(), !mime.isEmpty else {
            return "FILE"
        }
        if mime.contains("pdf") {
            return "PDF"
        }
        if mime.contains("text") {
            return "TXT"
        }
        if mime.contains("image") {
            return "IMG"
        }
        if mime.contains("word") || mime.contains("document") {
            return "DOC"
        }
        return "FILE"
    }

    var fileTypeDisplayText: String {
        guard let mime, !mime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Unknown type"
        }
        return mime
    }

    var metadataDisplayText: String {
        "\(displaySizeText) · \(fileTypeDisplayText)"
    }

    var hasLocalFile: Bool {
        if case .available = localFileState {
            return true
        }
        return false
    }

    var localFileStatusText: String {
        switch localFileState {
        case .waitingForLocalFile:
            return "No local file yet"
        case .available:
            return "Local file ready"
        }
    }

    var extractionStatusText: String {
        switch extractionState {
        case .waitingForLocalFile:
            return "Text not extracted"
        case .pending(let status):
            return statusDetail(prefix: "Extraction queued", detail: status)
        case .running(let status):
            return statusDetail(prefix: "Extracting text", detail: status)
        case .succeeded(let version, _):
            return "Text extracted · v\(version)"
        case .unsupported(_, let message):
            return statusDetail(prefix: "Format not supported", detail: message)
        case .failed(_, let message):
            return statusDetail(prefix: "Processing error", detail: message)
        }
    }

    var summaryStatusText: String {
        switch summaryState {
        case .available:
            return "Summary ready"
        case .failed(_, let message):
            return statusDetail(prefix: "Summary error", detail: message)
        case .unavailable:
            switch extractionState {
            case .waitingForLocalFile:
                return "Summary unavailable until text is extracted"
            case .pending, .running:
                return "Summary pending"
            case .succeeded:
                return "No local summary yet"
            case .unsupported:
                return "Summary unavailable for unsupported format"
            case .failed:
                return "Summary unavailable because processing failed"
            }
        }
    }

    func canPreviewAttachment(hasHandler: Bool) -> Bool {
        hasHandler && hasLocalFile
    }

    func canSummarizeAttachment(hasHandler: Bool) -> Bool {
        hasHandler && hasLocalFile && !isUnsupportedFormat
    }

    private var displaySizeText: String {
        if !formattedSize.isEmpty {
            return formattedSize
        }
        if case .available(let byteCount, _) = localFileState, let byteCount {
            return Self.formatBytes(byteCount)
        }
        return "Size unknown"
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        if bytes < 1024 * 1024 {
            return "\(bytes / 1024) KB"
        }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

extension AttachmentSummaryViewData {
    var confidenceDisplayText: String {
        "\(Int((confidence * 100).rounded()))% confidence"
    }

    var evidenceDisplayText: String {
        Self.evidenceText(for: evidenceChunkIds)
    }

    static func evidenceText(for chunkIds: [String]) -> String {
        guard !chunkIds.isEmpty else {
            return "No relevant fragments."
        }
        return "Evidence: \(chunkIds.joined(separator: ", "))"
    }
}

private func statusDetail(prefix: String, detail: String?) -> String {
    guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
        return prefix
    }
    return "\(prefix): \(detail)"
}
