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
