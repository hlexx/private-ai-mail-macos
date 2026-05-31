import Foundation
import OSLog

public enum PrivacyObservability {
    public static let subsystem = "com.hlexx.privateaimail"

    public static func logger(for category: PrivacyObservabilityCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    public static func event(
        _ name: String,
        category: PrivacyObservabilityCategory,
        metadata: [String: String] = [:]
    ) -> PrivacyObservabilityEvent {
        PrivacyObservabilityEvent(category: category, name: name, metadata: metadata)
    }

    public static func log(
        _ event: PrivacyObservabilityEvent,
        severity: PrivacyObservabilitySeverity = .info
    ) {
        let logger = logger(for: event.category)
        logger.log(level: severity.osLogType, "\(event.name, privacy: .public) \(event.metadataDescription, privacy: .public)")
    }

    public static func durationMillisecondsString(_ duration: Duration) -> String {
        let components = duration.components
        let secondsMilliseconds = components.seconds * 1_000
        let attosecondsMilliseconds = components.attoseconds / 1_000_000_000_000_000
        return "\(secondsMilliseconds + attosecondsMilliseconds)"
    }
}

public enum PrivacyObservabilitySeverity: Sendable {
    case debug
    case info
    case warning
    case error

    fileprivate var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}

public enum PrivacyObservabilityCategory: String, CaseIterable, Sendable {
    case sync = "Sync"
    case providerAuth = "ProviderAuth"
    case sendQueue = "SendQueue"
    case search = "Search"
    case attachment = "Attachment"
    case privacy = "Privacy"
    case ai = "AI"
}

public enum PrivacyObservabilityField: String, CaseIterable, Sendable {
    case accountID = "account_id"
    case accountHash = "account_hash"
    case provider
    case operation
    case status
    case durationMilliseconds = "duration_ms"
    case errorCategory = "error_category"
    case count
    case itemCount = "item_count"
    case messageCount = "message_count"
    case attachmentCount = "attachment_count"
    case retryNumber = "retry_number"
    case sizeBucket = "size_bucket"
    case capabilityFlag = "capability_flag"
    case featureFlag = "feature_flag"
    case featureFlags = "feature_flags"
    case appVersion = "app_version"
    case schemaVersion = "schema_version"
}

public struct PrivacyObservabilityEvent: Equatable, Sendable {
    public let category: PrivacyObservabilityCategory
    public let name: String
    public let metadata: [String: String]

    public init(
        category: PrivacyObservabilityCategory,
        name: String,
        fields: [PrivacyObservabilityField: String]
    ) {
        self.init(
            category: category,
            name: name,
            metadata: Dictionary(uniqueKeysWithValues: fields.map { ($0.rawValue, $1) })
        )
    }

    public init(
        category: PrivacyObservabilityCategory,
        name: String,
        metadata: [String: String] = [:]
    ) {
        self.category = category
        self.name = PrivacyObservabilityRedactor.sanitizedEventName(name)
        self.metadata = PrivacyObservabilityRedactor.sanitizedMetadata(metadata)
    }

    public var metadataDescription: String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}

public enum PrivacyObservabilityRedactor {
    public static let redactedValue = "[redacted]"

    public static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [String: String]()) { result, pair in
            let key = canonicalKey(pair.key)

            guard shouldKeepField(named: key) else {
                return
            }

            result[key] = sanitizedValue(pair.value, forKey: key)
        }
    }

    public static func sanitizedEventName(_ name: String) -> String {
        sanitizedValue(name, forKey: PrivacyObservabilityField.operation.rawValue)
    }

    public static func sanitizedValue(_ value: String, forKey key: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return trimmed
        }

        if containsSensitiveValue(trimmed, key: canonicalKey(key)) {
            return redactedValue
        }

        return trimmed
    }

    public static func shouldKeepField(named key: String) -> Bool {
        let key = canonicalKey(key)
        return approvedFieldKeys.contains(key)
    }

    public static func canonicalKey(_ key: String) -> String {
        let snakeCase = key.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1_$2",
            options: .regularExpression
        )
        let normalized = snakeCase
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber {
                    return character
                }
                return "_"
            }

        return String(normalized)
            .split(separator: "_")
            .joined(separator: "_")
    }

    private static let approvedFieldKeys = Set(PrivacyObservabilityField.allCases.map(\.rawValue))

    private static let sensitiveKeyTokens: Set<String> = [
        "address",
        "api",
        "attachment",
        "authorization",
        "bcc",
        "bearer",
        "body",
        "cc",
        "checkpoint",
        "chunk",
        "client",
        "code",
        "contact",
        "content",
        "context",
        "cookie",
        "cursor",
        "delta",
        "document",
        "email",
        "evidence",
        "extracted",
        "file",
        "filename",
        "from",
        "headers",
        "history",
        "html",
        "key",
        "mime",
        "model",
        "output",
        "payload",
        "preview",
        "prompt",
        "query",
        "raw",
        "recipient",
        "recipients",
        "request",
        "response",
        "secret",
        "sender",
        "snippet",
        "subject",
        "summary",
        "text",
        "to",
        "token",
        "url"
    ]

    private static let tokenParameterNames = [
        "access" + "_token",
        "refresh" + "_token",
        "client" + "_secret",
        "api" + "_key",
        "authorization" + "_code",
        "id" + "_token"
    ]

    private static let tokenValuePatterns = [
        #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#,
        "(?i)\\b(\(tokenParameterNames.joined(separator: "|")))=\\S+",
        #"(?i)\bya29\.[A-Za-z0-9._-]+"#,
        #"(?i)\b(sk|xox[baprs])-?[A-Za-z0-9._-]{16,}"#,
        #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#
    ]

    private static func tokens(for key: String) -> Set<String> {
        Set(canonicalKey(key).split(separator: "_").map(String.init))
    }

    private static func containsSensitiveValue(_ value: String, key: String) -> Bool {
        let lowercased = value.lowercased()

        if key != PrivacyObservabilityField.accountID.rawValue,
           value.range(
               of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
               options: [.regularExpression, .caseInsensitive]
           ) != nil {
            return true
        }

        if lowercased.contains("<html")
            || lowercased.contains("<body")
            || lowercased.contains("content-type:")
            || lowercased.contains("mime-version:")
            || lowercased.contains("\r\n\r\n")
            || lowercased.contains("\n\n") {
            return true
        }

        return tokenValuePatterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
