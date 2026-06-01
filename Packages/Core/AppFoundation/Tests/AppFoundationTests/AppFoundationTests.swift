import Foundation
import Testing
@testable import AppFoundation

@Suite("AppFoundation")
struct AppFoundationTests {
    @Test func moduleNameIsExported() {
        #expect(AppFoundation.moduleName == "AppFoundation")
    }

    @Test func privacyObservabilityCategoriesCoverTrustMVPSubsystems() {
        #expect(PrivacyObservabilityCategory.allCases.map(\.rawValue) == [
            "Sync",
            "ProviderAuth",
            "SendQueue",
            "Search",
            "Attachment",
            "Privacy",
            "AI"
        ])
    }

    @Test func userActionableFailureCategoriesCoverTrustMVPStates() {
        #expect(UserActionableFailureCategory.allCases.map(\.rawValue) == [
            "offline",
            "missingCredential",
            "insufficientScope",
            "rateLimit",
            "providerUnavailable",
            "unsupportedOperation",
            "unknown"
        ])
    }

    @Test func userActionableFailureMessagesAreCategorySpecificAndSanitized() {
        let failures = UserActionableFailureCategory.allCases.map {
            UserActionableFailure(category: $0, operation: .sync, provider: "Gmail", retryAfterSeconds: 30)
        }

        #expect(failures.map(\.message).allSatisfy { !$0.isEmpty })
        #expect(failures.first { $0.category == .offline }?.message.contains("offline") == true)
        #expect(failures.first { $0.category == .missingCredential }?.message.contains("Reconnect") == true)
        #expect(failures.first { $0.category == .insufficientScope }?.message.contains("Re-authorize") == true)
        #expect(failures.first { $0.category == .rateLimit }?.message.contains("30s") == true)
        #expect(failures.first { $0.category == .providerUnavailable }?.message.contains("unavailable") == true)
        #expect(failures.first { $0.category == .unsupportedOperation }?.message.contains("not supported") == true)
        #expect(failures.first { $0.category == .unknown }?.message.contains("unknown") == true)
        #expect(!failures.map(\.message).joined(separator: " ").localizedCaseInsensitiveContains("body"))
        #expect(!failures.map(\.message).joined(separator: " ").localizedCaseInsensitiveContains("token"))
        #expect(!failures.map(\.message).joined(separator: " ").localizedCaseInsensitiveContains("payload"))
    }

    @Test func userActionableFailureCoercesNetworkErrorsWithoutRawDetails() {
        let failure = UserActionableFailure.coerce(
            URLError(.notConnectedToInternet),
            operation: .search,
            provider: "Gmail"
        )

        #expect(failure.category == .offline)
        #expect(failure.message == "Search cannot reach Gmail while offline. Check your connection and try again.")
    }

    @Test func privacyObservabilityKeepsApprovedSafeFields() {
        let event = PrivacyObservability.event(
            "sync.completed",
            category: .sync,
            metadata: [
                "accountID": "local-account-1",
                "provider": "gmail",
                "operation": "delta_sync",
                "status": "completed",
                "durationMS": "42",
                "errorCategory": "none",
                "attachmentCount": "3",
                "featureFlags": "trust_mvp"
            ]
        )

        #expect(event.metadata == [
            "account_id": "local-account-1",
            "provider": "gmail",
            "operation": "delta_sync",
            "status": "completed",
            "duration_ms": "42",
            "error_category": "none",
            "attachment_count": "3",
            "feature_flags": "trust_mvp"
        ])
    }

    @Test func privacyObservabilityDropsSensitiveContentFields() {
        let metadata = PrivacyObservabilityRedactor.sanitizedMetadata([
            "messageBody": "Please review the contract terms.",
            "htmlBody": "<html><body>raw mail</body></html>",
            "mimeBody": "Content-Type: text/plain\r\n\r\nraw MIME body",
            "promptContext": "Summarize this private thread.",
            "attachmentFilename": "customer-statement.pdf",
            "refreshToken": "refresh-token-value",
            "threadID": "thread-123",
            "messageID": "message-456",
            "attachmentID": "attachment-789",
            "labelName": "Client A",
            "operation": "sync",
            "count": "2"
        ])

        #expect(metadata == [
            "operation": "sync",
            "count": "2"
        ])
    }

    @Test func privacyObservabilityRedactsSensitiveValuesInSafeFields() {
        let metadata = PrivacyObservabilityRedactor.sanitizedMetadata([
            "status": "Bearer ya29.secret-token",
            "operation": "Content-Type: text/plain\r\n\r\nprivate MIME content",
            "errorCategory": "sent to alex@example.com",
            "provider": "gmail"
        ])

        #expect(metadata == [
            "status": PrivacyObservabilityRedactor.redactedValue,
            "operation": PrivacyObservabilityRedactor.redactedValue,
            "error_category": PrivacyObservabilityRedactor.redactedValue,
            "provider": "gmail"
        ])
    }

    @Test func privacyObservabilityTypedFieldsBuildSanitizedEvents() {
        let event = PrivacyObservabilityEvent(
            category: .sendQueue,
            name: "send.retry",
            fields: [
                .accountHash: "acc_123",
                .provider: "outlook",
                .operation: "send",
                .status: "retrying",
                .retryNumber: "2"
            ]
        )

        #expect(event.metadataDescription == "account_hash=acc_123 operation=send provider=outlook retry_number=2 status=retrying")
    }

    @Test func appLoggingSurfacesUseSanitizedObservability() throws {
        let root = try Self.repositoryRoot()
        let scannedDirectories = [
            "Apps/MacApp/Sources",
            "Packages/Mail/MailSync/Sources",
            "Packages/Mail/MailProviders/Sources",
            "Packages/Mail/MailIndex/Sources",
            "Packages/Features/SettingsFeature/Sources",
            "Packages/Features/ComposeFeature/Sources",
            "Packages/Features/BriefFeature/Sources",
            "Packages/Features/ThreadFeature/Sources",
            "Packages/Features/InboxFeature/Sources",
            "Packages/Attachments/AttachmentRAG/Sources",
            "Packages/AI/AIRuntime/Sources",
            "Packages/AI/AIEvals/Sources"
        ]

        let forbiddenFragments = [
            "Logger(",
            "logger.",
            "os_log(",
            "print("
        ]
        var violations: [String] = []

        for directory in scannedDirectories {
            let directoryURL = root.appending(path: directory)
            for fileURL in try Self.swiftFiles(under: directoryURL) {
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                for fragment in forbiddenFragments where text.contains(fragment) {
                    let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                    violations.append("\(relativePath) contains \(fragment)")
                }
            }
        }

        #expect(violations == [])
    }

    private static func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private static func swiftFiles(under directoryURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let fileURL = item as? URL, fileURL.pathExtension == "swift" else {
                return nil
            }
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            return resourceValues.isRegularFile == true ? fileURL : nil
        }
    }
}
