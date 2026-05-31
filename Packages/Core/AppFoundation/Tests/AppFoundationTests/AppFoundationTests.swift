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
}
