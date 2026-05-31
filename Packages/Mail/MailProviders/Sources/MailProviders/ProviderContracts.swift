import Foundation
import MailDomain

public struct MailProviderCapabilities: Sendable, Equatable {
    public let supportsLabels: Bool
    public let supportsFolders: Bool
    public let supportsCategories: Bool
    public let supportsSend: Bool
    public let supportsAttachmentDownload: Bool
    public let supportsDeltaSync: Bool
    public let supportsServerSearch: Bool
    public let supportsAliases: Bool

    public init(
        supportsLabels: Bool,
        supportsFolders: Bool,
        supportsCategories: Bool,
        supportsSend: Bool,
        supportsAttachmentDownload: Bool,
        supportsDeltaSync: Bool,
        supportsServerSearch: Bool,
        supportsAliases: Bool
    ) {
        self.supportsLabels = supportsLabels
        self.supportsFolders = supportsFolders
        self.supportsCategories = supportsCategories
        self.supportsSend = supportsSend
        self.supportsAttachmentDownload = supportsAttachmentDownload
        self.supportsDeltaSync = supportsDeltaSync
        self.supportsServerSearch = supportsServerSearch
        self.supportsAliases = supportsAliases
    }
}

public extension MailProviderCapabilities {
    static let gmail = MailProviderCapabilities(
        supportsLabels: true,
        supportsFolders: false,
        supportsCategories: false,
        supportsSend: true,
        supportsAttachmentDownload: true,
        supportsDeltaSync: true,
        supportsServerSearch: true,
        supportsAliases: true
    )

    static let outlook = MailProviderCapabilities(
        supportsLabels: false,
        supportsFolders: true,
        supportsCategories: true,
        supportsSend: true,
        supportsAttachmentDownload: true,
        supportsDeltaSync: true,
        supportsServerSearch: true,
        supportsAliases: true
    )
}

public enum MailProviderErrorCategory: String, Codable, Sendable, CaseIterable {
    case missingCredential
    case insufficientScope
    case authExpired
    case rateLimited
    case offline
    case providerUnavailable
    case notFound
    case invalidResponse
    case unsupportedOperation
    case conflict
}

public extension GmailAPIError {
    var sharedCategory: MailProviderErrorCategory {
        switch self {
        case .missingAttachmentIdentifier:
            return .invalidResponse
        case .unauthorized:
            return .authExpired
        case .rateLimited:
            return .rateLimited
        case .serverError(let statusCode):
            return Self.mapServerStatus(statusCode)
        case .networkError:
            return .offline
        case .decodingError, .invalidResponse:
            return .invalidResponse
        case .insufficientScope:
            return .insufficientScope
        case .exhaustedRetries:
            return .providerUnavailable
        }
    }

    private static func mapServerStatus(_ statusCode: Int) -> MailProviderErrorCategory {
        switch statusCode {
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 429:
            return .rateLimited
        case 501:
            return .unsupportedOperation
        case 500 ... 599:
            return .providerUnavailable
        default:
            return .providerUnavailable
        }
    }
}

public extension GmailAPIError {
    var sendFailureCategory: SendFailureCategory {
        switch self {
        case .missingAttachmentIdentifier:
            return .validation
        case .unauthorized:
            return .authExpired
        case .rateLimited:
            return .rateLimited
        case .serverError(let statusCode):
            return Self.mapServerStatusToSendFailureCategory(statusCode)
        case .networkError(let error):
            return Self.mapNetworkError(error)
        case .decodingError, .invalidResponse:
            return .invalidResponse
        case .insufficientScope:
            return .insufficientScope
        case .exhaustedRetries:
            return .providerUnavailable
        }
    }

    func sanitizedSendFailure(occurredAt: Date = Date()) -> SanitizedSendFailure {
        SanitizedSendFailure(
            category: sendFailureCategory,
            providerErrorCode: sendProviderErrorCode,
            retryAfterSeconds: sendRetryAfterSeconds,
            occurredAt: occurredAt
        )
    }

    private var sendProviderErrorCode: String? {
        switch self {
        case .missingAttachmentIdentifier:
            return "missing_attachment_id"
        case .unauthorized:
            return "401"
        case .rateLimited:
            return "429"
        case .serverError(let statusCode):
            return "\(statusCode)"
        case .networkError(let error):
            if let urlError = error as? URLError {
                return urlError.code.rawValue.description
            }
            return "network"
        case .decodingError:
            return "decoding"
        case .insufficientScope:
            return "insufficient_scope"
        case .exhaustedRetries:
            return "exhausted_retries"
        case .invalidResponse:
            return "invalid_response"
        }
    }

    private var sendRetryAfterSeconds: Int? {
        guard case .rateLimited(let retryAfter) = self,
              let retryAfter else {
            return nil
        }
        return Int(retryAfter)
    }

    private static func mapServerStatusToSendFailureCategory(_ statusCode: Int) -> SendFailureCategory {
        switch statusCode {
        case 400 ... 499 where statusCode != 404 && statusCode != 409 && statusCode != 429:
            return .validation
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 429:
            return .rateLimited
        case 501:
            return .unsupportedOperation
        case 500 ... 599:
            return .providerUnavailable
        default:
            return .providerUnavailable
        }
    }

    private static func mapNetworkError(_ error: any Error) -> SendFailureCategory {
        guard let urlError = error as? URLError else {
            return .offline
        }
        return urlError.code == .timedOut ? .timeout : .offline
    }
}

public extension GraphAPIError {
    var sendFailureCategory: SendFailureCategory {
        switch self {
        case .missingAttachmentIdentifier:
            return .validation
        case .unauthorized:
            return .authExpired
        case .rateLimited:
            return .rateLimited
        case .serverError(let statusCode, _):
            return Self.mapServerStatusToSendFailureCategory(statusCode)
        case .networkError(let description):
            return description.localizedCaseInsensitiveContains("timedout")
                || description.localizedCaseInsensitiveContains("timed out")
                ? .timeout
                : .offline
        case .decodingError, .invalidResponse:
            return .invalidResponse
        case .insufficientScope:
            return .insufficientScope
        }
    }

    func sanitizedSendFailure(occurredAt: Date = Date()) -> SanitizedSendFailure {
        SanitizedSendFailure(
            category: sendFailureCategory,
            providerErrorCode: sendProviderErrorCode,
            retryAfterSeconds: sendRetryAfterSeconds,
            occurredAt: occurredAt
        )
    }

    private var sendProviderErrorCode: String? {
        switch self {
        case .missingAttachmentIdentifier:
            return "missing_attachment_id"
        case .unauthorized:
            return "401"
        case .rateLimited:
            return "429"
        case .serverError(let statusCode, let code):
            return code ?? "\(statusCode)"
        case .networkError:
            return "network"
        case .decodingError:
            return "decoding"
        case .insufficientScope:
            return "insufficient_scope"
        case .invalidResponse:
            return "invalid_response"
        }
    }

    private var sendRetryAfterSeconds: Int? {
        guard case .rateLimited(let retryAfter) = self,
              let retryAfter else {
            return nil
        }
        return Int(retryAfter)
    }

    private static func mapServerStatusToSendFailureCategory(_ statusCode: Int) -> SendFailureCategory {
        switch statusCode {
        case 400 ... 499 where statusCode != 404 && statusCode != 409 && statusCode != 429:
            return .validation
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 429:
            return .rateLimited
        case 501:
            return .unsupportedOperation
        case 500 ... 599:
            return .providerUnavailable
        default:
            return .providerUnavailable
        }
    }
}
