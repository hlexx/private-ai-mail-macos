import Foundation
import PDFKit
import Vision

// MARK: - Extraction Contracts

public protocol AttachmentExtractor: Sendable {
    func extract(_ input: AttachmentExtractionInput) -> AttachmentExtractionResult
}

public struct AttachmentExtractionInput: Sendable {
    public var key: AttachmentByteKey?
    public var filename: String?
    public var mimeType: String?
    public var data: Data
    public var ocrPolicy: AttachmentOCRPolicy

    public init(
        key: AttachmentByteKey? = nil,
        filename: String? = nil,
        mimeType: String? = nil,
        data: Data,
        ocrPolicy: AttachmentOCRPolicy = .disabled
    ) {
        self.key = key
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.ocrPolicy = ocrPolicy
    }
}

public enum AttachmentOCRPolicy: Equatable, Sendable {
    case disabled
    case vision(minimumConfidence: Float = 0.55)
}

public enum AttachmentExtractionStatus: String, Sendable {
    case complete
    case incomplete
    case unsupported
    case failed
}

public struct AttachmentImageRegion: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum AttachmentEvidenceLocator: Equatable, Sendable {
    case page(number: Int)
    case byteRange(start: Int, end: Int)
    case section(name: String)
    case imageRegion(AttachmentImageRegion, confidence: Float)
}

public struct AttachmentExtractedText: Equatable, Sendable {
    public var text: String
    public var locator: AttachmentEvidenceLocator

    public init(text: String, locator: AttachmentEvidenceLocator) {
        self.text = text
        self.locator = locator
    }
}

public enum AttachmentExtractionFailureCode: String, Sendable {
    case unsupportedType
    case unsupportedDocumentFormat
    case ocrDisabled
    case ocrUnavailable
    case ocrLowConfidence
    case unreadablePDF
    case undecodableText
    case noExtractableText
}

public struct AttachmentExtractionFailure: Error, Equatable, Sendable {
    public var code: AttachmentExtractionFailureCode
    public var userFacingReason: String
    public var technicalReason: String
    public var locator: AttachmentEvidenceLocator?

    public init(
        code: AttachmentExtractionFailureCode,
        userFacingReason: String,
        technicalReason: String,
        locator: AttachmentEvidenceLocator? = nil
    ) {
        self.code = code
        self.userFacingReason = userFacingReason
        self.technicalReason = technicalReason
        self.locator = locator
    }
}

extension AttachmentExtractionFailure: LocalizedError {
    public var errorDescription: String? {
        userFacingReason
    }
}

public struct AttachmentExtractionResult: Equatable, Sendable {
    public var status: AttachmentExtractionStatus
    public var extractedText: [AttachmentExtractedText]
    public var failures: [AttachmentExtractionFailure]

    public init(
        status: AttachmentExtractionStatus,
        extractedText: [AttachmentExtractedText] = [],
        failures: [AttachmentExtractionFailure] = []
    ) {
        self.status = status
        self.extractedText = extractedText
        self.failures = failures
    }

    public var combinedText: String {
        extractedText.map(\.text).joined(separator: "\n\n")
    }
}

// MARK: - Platform Extractor

public struct PlatformAttachmentExtractor: AttachmentExtractor {
    public init() {}

    public func extract(_ input: AttachmentExtractionInput) -> AttachmentExtractionResult {
        switch AttachmentContentFamily(input: input) {
        case .pdf:
            return extractPDF(input)
        case .html:
            return extractHTML(input)
        case .text:
            return extractText(input)
        case .docx:
            return unsupported(
                code: .unsupportedDocumentFormat,
                reason: "DOCX extraction is not available yet.",
                technicalReason: "No lightweight DOCX parser exists in the workspace.",
                input: input
            )
        case .image:
            return extractImage(input)
        case .unsupported:
            return unsupported(
                code: .unsupportedType,
                reason: "This attachment type is not supported for text extraction yet.",
                technicalReason: """
                Unsupported MIME type '\(input.mimeType ?? "unknown")' and \
                filename '\(input.filename ?? "unknown")'.
                """,
                input: input
            )
        }
    }

    private func extractPDF(_ input: AttachmentExtractionInput) -> AttachmentExtractionResult {
        guard let document = PDFDocument(data: input.data) else {
            return AttachmentExtractionResult(
                status: .failed,
                failures: [
                    AttachmentExtractionFailure(
                        code: .unreadablePDF,
                        userFacingReason: "The PDF could not be opened for text extraction.",
                        technicalReason: "PDFKit returned nil for the attachment data.",
                        locator: .section(name: "pdf")
                    ),
                ]
            )
        }

        if document.isEncrypted, !document.allowsCopying {
            return AttachmentExtractionResult(
                status: .failed,
                failures: [
                    AttachmentExtractionFailure(
                        code: .unreadablePDF,
                        userFacingReason: "The PDF is encrypted or does not allow text extraction.",
                        technicalReason: "PDFKit reported an encrypted document without copy permission.",
                        locator: .section(name: "pdf")
                    ),
                ]
            )
        }

        var sections: [AttachmentExtractedText] = []
        var failures: [AttachmentExtractionFailure] = []
        for pageIndex in 0..<document.pageCount {
            let pageNumber = pageIndex + 1
            let text = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                failures.append(
                    AttachmentExtractionFailure(
                        code: .noExtractableText,
                        userFacingReason: "One or more PDF pages did not contain selectable text.",
                        technicalReason: "PDF page \(pageNumber) returned empty text.",
                        locator: .page(number: pageNumber)
                    )
                )
            } else {
                sections.append(AttachmentExtractedText(text: text, locator: .page(number: pageNumber)))
            }
        }

        guard !sections.isEmpty else {
            return AttachmentExtractionResult(status: .incomplete, failures: failures.isEmpty ? [
                AttachmentExtractionFailure(
                    code: .noExtractableText,
                    userFacingReason: "The PDF did not contain extractable text.",
                    technicalReason: "PDF had no pages with selectable text.",
                    locator: .section(name: "pdf")
                ),
            ] : failures)
        }

        return AttachmentExtractionResult(
            status: failures.isEmpty ? .complete : .incomplete,
            extractedText: sections,
            failures: failures
        )
    }

    private func extractText(_ input: AttachmentExtractionInput) -> AttachmentExtractionResult {
        guard let text = decodeText(input.data)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return AttachmentExtractionResult(
                status: .incomplete,
                failures: [
                    AttachmentExtractionFailure(
                        code: .undecodableText,
                        userFacingReason: "The text attachment could not be decoded.",
                        technicalReason: "Supported string encodings did not produce non-empty text.",
                        locator: .byteRange(start: 0, end: input.data.count)
                    ),
                ]
            )
        }

        return AttachmentExtractionResult(
            status: .complete,
            extractedText: [
                AttachmentExtractedText(text: text, locator: .byteRange(start: 0, end: input.data.count)),
            ]
        )
    }

    private func extractHTML(_ input: AttachmentExtractionInput) -> AttachmentExtractionResult {
        guard let html = decodeText(input.data), let text = htmlToPlainText(html) else {
            return AttachmentExtractionResult(
                status: .incomplete,
                failures: [
                    AttachmentExtractionFailure(
                        code: .undecodableText,
                        userFacingReason: "The HTML attachment could not be converted to text.",
                        technicalReason: "Supported string encodings did not produce non-empty HTML text.",
                        locator: .byteRange(start: 0, end: input.data.count)
                    ),
                ]
            )
        }

        return AttachmentExtractionResult(
            status: .complete,
            extractedText: [
                AttachmentExtractedText(text: text, locator: .byteRange(start: 0, end: input.data.count)),
            ]
        )
    }

    private func extractImage(_ input: AttachmentExtractionInput) -> AttachmentExtractionResult {
        switch input.ocrPolicy {
        case .disabled:
            return AttachmentExtractionResult(
                status: .incomplete,
                failures: [
                    AttachmentExtractionFailure(
                        code: .ocrDisabled,
                        userFacingReason: "Image OCR is disabled for this attachment.",
                        technicalReason: "Attachment matched an image type but OCR policy was disabled.",
                        locator: .section(name: "ocr")
                    ),
                ]
            )
        case let .vision(minimumConfidence):
            return extractImageWithVision(input, minimumConfidence: minimumConfidence)
        }
    }

    private func extractImageWithVision(
        _ input: AttachmentExtractionInput,
        minimumConfidence: Float
    ) -> AttachmentExtractionResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(data: input.data, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return AttachmentExtractionResult(
                status: .incomplete,
                failures: [
                    AttachmentExtractionFailure(
                        code: .ocrUnavailable,
                        userFacingReason: "Image text recognition could not read this attachment.",
                        technicalReason: String(describing: error),
                        locator: .section(name: "ocr")
                    ),
                ]
            )
        }

        let observations = request.results ?? []
        var sections: [AttachmentExtractedText] = []
        var lowConfidenceCount = 0
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            if candidate.confidence < minimumConfidence {
                lowConfidenceCount += 1
                continue
            }
            let box = observation.boundingBox
            sections.append(
                AttachmentExtractedText(
                    text: candidate.string,
                    locator: .imageRegion(
                        AttachmentImageRegion(
                            x: Double(box.origin.x),
                            y: Double(box.origin.y),
                            width: Double(box.width),
                            height: Double(box.height)
                        ),
                        confidence: candidate.confidence
                    )
                )
            )
        }

        if sections.isEmpty {
            return AttachmentExtractionResult(
                status: .incomplete,
                failures: [
                    AttachmentExtractionFailure(
                        code: lowConfidenceCount > 0 ? .ocrLowConfidence : .noExtractableText,
                        userFacingReason: lowConfidenceCount > 0
                            ? "Image OCR found text, but confidence was too low to use."
                            : "Image OCR did not find readable text.",
                        technicalReason: lowConfidenceCount > 0
                            ? "All Vision OCR candidates were below confidence \(minimumConfidence)."
                            : "Vision OCR returned no accepted text observations.",
                        locator: .section(name: "ocr")
                    ),
                ]
            )
        }

        let failures: [AttachmentExtractionFailure] = lowConfidenceCount > 0 ? [
            AttachmentExtractionFailure(
                code: .ocrLowConfidence,
                userFacingReason: "Some image text was omitted because OCR confidence was too low.",
                technicalReason: "\(lowConfidenceCount) Vision OCR candidates were below confidence \(minimumConfidence).",
                locator: .section(name: "ocr")
            ),
        ] : []

        return AttachmentExtractionResult(
            status: failures.isEmpty ? .complete : .incomplete,
            extractedText: sections,
            failures: failures
        )
    }

    private func unsupported(
        code: AttachmentExtractionFailureCode,
        reason: String,
        technicalReason: String,
        input: AttachmentExtractionInput
    ) -> AttachmentExtractionResult {
        AttachmentExtractionResult(
            status: .unsupported,
            failures: [
                AttachmentExtractionFailure(
                    code: code,
                    userFacingReason: reason,
                    technicalReason: technicalReason,
                    locator: .section(name: input.filename ?? input.mimeType ?? "attachment")
                ),
            ]
        )
    }
}

// MARK: - Helpers

private enum AttachmentContentFamily {
    case pdf
    case html
    case text
    case docx
    case image
    case unsupported

    init(input: AttachmentExtractionInput) {
        let mime = input.mimeType?.lowercased()
        let ext = input.filename?
            .split(separator: ".")
            .last
            .map { String($0).lowercased() }

        if mime == "application/pdf" || ext == "pdf" {
            self = .pdf
        } else if mime == "text/html" || ext == "html" || ext == "htm" {
            self = .html
        } else if mime == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" || ext == "docx" {
            self = .docx
        } else if mime?.hasPrefix("image/") == true
            || ext.map({ ["png", "jpg", "jpeg", "tif", "tiff", "heic"].contains($0) }) == true {
            self = .image
        } else if Self.isTextMime(mime)
            || ext.map({ ["txt", "csv", "md", "markdown", "json", "xml", "yaml", "yml"].contains($0) }) == true {
            self = .text
        } else {
            self = .unsupported
        }
    }

    private static func isTextMime(_ mime: String?) -> Bool {
        guard let mime else { return false }
        return mime.hasPrefix("text/")
            || mime == "application/json"
            || mime == "application/xml"
            || mime == "application/x-yaml"
            || mime == "application/yaml"
    }
}

private func decodeText(_ data: Data) -> String? {
    for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1] {
        if let text = String(data: data, encoding: encoding) {
            return text
        }
    }
    return nil
}

private func htmlToPlainText(_ html: String) -> String? {
    var text = html
        .replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
    text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
    text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: "&amp;", with: "&")
    text = text.replacingOccurrences(of: "&lt;", with: "<")
    text = text.replacingOccurrences(of: "&gt;", with: ">")
    text = text.replacingOccurrences(of: "&quot;", with: "\"")
    text = text.replacingOccurrences(of: "&#39;", with: "'")
    text = text.replacingOccurrences(of: "&nbsp;", with: " ")
    while text.contains("\n\n\n") {
        text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
