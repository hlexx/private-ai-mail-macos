import Foundation
import Testing

@Suite("Trust MVP sequencing document")
struct TrustMVPSequencingDocumentTests {
    @Test func documentNamesEightTranchesAndDeferredTrustMVPCapabilities() throws {
        let document = try Self.loadSequencingDocument()

        for number in 1...8 {
            #expect(document.contains("### Tranche \(number):"))
        }

        #expect(document.contains("Microsoft Graph network calls: implemented in provider/sync packages but"))
        #expect(document.contains("product-disabled"))
        #expect(document.contains("Full local search: implemented for synced local mail through the local index."))
        #expect(document.contains("Send and action queues: implemented for Gmail Trust MVP flows."))
        #expect(document.contains("Broad DOCX/OCR,"))
        #expect(document.contains("archive extraction, and arbitrary attachment preview remain deferred."))
        #expect(document.contains("mutations, Snooze, automatic rules, Slack/Notion/CRM writes"))
        #expect(document.contains("notarized packaging remain release-owner manual"))
    }

    @Test func documentKeepsEMAILALFFollowUpOutOfAppPlan() throws {
        let document = try Self.loadSequencingDocument()

        #expect(document.contains("Do not edit `../EMAIL_ALF` from this app implementation plan."))
        #expect(document.contains("`../EMAIL_ALF/04_product_requirements.md`"))
        #expect(document.contains("`../EMAIL_ALF/07_architecture.md`"))
        #expect(document.contains("`../EMAIL_ALF/08_security_privacy.md`"))
        #expect(document.contains("`../EMAIL_ALF/10_roadmap.md`"))
    }

    @Test func adrRecordsMicrosoftGraphDeltaScopesAndNonGoals() throws {
        let document = try Self.loadADR0005()

        #expect(document.contains("Message delta is scoped to one mail folder at a time."))
        #expect(document.contains("`@odata.nextLink`"))
        #expect(document.contains("`@odata.deltaLink`"))
        #expect(document.contains("opaque to the client"))
        #expect(document.contains("`Mail.ReadWrite`"))
        #expect(document.contains("`Mail.Send`"))
        #expect(document.contains("`offline_access`"))
        #expect(document.contains("`openid`, `profile`, and `email`"))
        #expect(document.contains("Application permissions and app-only daemon access are"))
        #expect(document.contains("shared mailboxes, delegated"))
        #expect(document.contains("https://learn.microsoft.com/en-us/graph/delta-query-messages"))
        #expect(document.contains("https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc"))
    }

    @Test func adrRecordsSendQueueSemanticsAndNonGoals() throws {
        let document = try Self.loadADR0005()

        #expect(document.contains("## Send Queue and Draft Reliability (Task 5)"))
        #expect(document.contains("`ComposeFeature` owns editing and"))
        #expect(document.contains("`MailDomain` owns draft identity"))
        #expect(document.contains("`Persistence` owns local draft and queue storage"))

        for state in [
            "`pending`",
            "`sending`",
            "`retryScheduled`",
            "`needsConsent`",
            "`failed`",
            "`sent`",
            "`canceled`",
            "`duplicateSuppressed`"
        ] {
            #expect(document.contains(state))
        }

        #expect(document.contains("1 minute, 5 minute, 15 minute, 1 hour, and 4 hour backoff"))
        #expect(document.contains("stable idempotency key"))
        #expect(document.contains("uniqueness for provider, account id, and"))
        #expect(document.contains("A duplicate Send click returns the existing queue row"))
        #expect(document.contains("Local sent rows may be"))
        #expect(document.contains("only after provider success is confirmed"))
        #expect(document.contains("provider-specific reconciliation"))
        #expect(document.contains("Gmail send"))
        #expect(document.contains("Microsoft Graph"))
        #expect(document.contains("delegated `Mail.Send` scope"))
        #expect(document.contains("Missing or"))
        #expect(document.contains("insufficient scope transitions the item to `needsConsent`"))
        #expect(document.contains("Users can cancel `pending`,"))
        #expect(document.contains("Draft bodies and queued outgoing bodies remain local"))
        #expect(document.contains("SQLite `AppDatabase`"))
        #expect(document.contains("`body_storage = sqlite`"))
        #expect(document.contains("send later, background delivery while the app is"))
        #expect(document.contains("AI auto-send, shared mailbox send-as, enterprise delegated send"))
    }

    @Test func privacyObservabilityDocumentDefinesDataClassesAndLogBoundary() throws {
        let document = try Self.loadPrivacyObservabilityDocument()

        for dataClass in [
            "Local raw mail",
            "Local attachments",
            "Local drafts",
            "Local indexes",
            "Local AI artifacts",
            "Provider API requests",
            "Optional cloud/control-plane metadata",
            "Approved external payloads"
        ] {
            #expect(document.contains(dataClass))
        }

        #expect(document.contains("No mailbox mirroring by default."))
        #expect(document.contains("Provider API calls for sync and send"))
        #expect(document.contains("Future approved integrations"))
        #expect(document.contains("Logs may contain:"))
        #expect(document.contains("Account id or hash."))
        #expect(document.contains("Provider."))
        #expect(document.contains("Operation."))
        #expect(document.contains("Status."))
        #expect(document.contains("Duration."))
        #expect(document.contains("Error category."))
        #expect(document.contains("Counts."))
        #expect(document.contains("Feature flags."))
        #expect(document.contains("Logs must not contain:"))
        #expect(document.contains("Raw mail body"))
        #expect(document.contains("Attachment bytes"))
        #expect(document.contains("AI prompts"))
        #expect(document.contains("OAuth access tokens"))
        #expect(document.contains("Raw provider request or response payloads."))
    }

    @Test func readmeStatesCurrentTrustMVPSupportHonestly() throws {
        let document = try Self.loadREADME()

        #expect(document.contains("Gmail is the stable Trust MVP provider path"))
        #expect(document.contains("Outlook/Microsoft 365 support is beta-disabled"))
        #expect(document.contains("Settings UI keeps Add Outlook"))
        #expect(document.contains("disabled for this release candidate"))
        #expect(document.contains("Local AI is an optional local assistant layer"))

        for nonGoal in [
            "iCloud Mail",
            "IMAP",
            "JMAP",
            "shared/delegated",
            "CRM writes",
            "Slack/Notion writes",
            "send later",
            "auto-send",
            "mobile companion apps"
        ] {
            #expect(document.contains(nonGoal))
        }

        #expect(!document.contains("revenue comes from workflow integrations"))
    }

    @Test func notesContainTrustMVPReleaseClaimChecklist() throws {
        let document = try Self.loadNOTES()

        #expect(document.contains("### Trust MVP release claim checklist"))
        #expect(document.contains("Use this checklist before editing README"))

        for claimArea in [
            "| Gmail |",
            "| M365 / Outlook |",
            "| FTS / local search |",
            "| DOCX / OCR |",
            "| Spotlight |",
            "| Send queue |",
            "| Privacy |",
            "| Local AI |"
        ] {
            #expect(document.contains(claimArea))
        }

        #expect(document.contains("Beta-disabled by default until real-account smoke tests pass"))
        #expect(document.contains("Do not edit sibling `../EMAIL_ALF`"))
    }

    private static func loadSequencingDocument() throws -> String {
        try loadDocument("docs/trust-mvp-sequencing.md")
    }

    private static func loadADR0005() throws -> String {
        try loadDocument("docs/adr/0005-trust-mvp-gmail-outlook-provider-contracts.md")
    }

    private static func loadPrivacyObservabilityDocument() throws -> String {
        try loadDocument("docs/trust-mvp-privacy-and-observability.md")
    }

    private static func loadREADME() throws -> String {
        try loadDocument("README.md")
    }

    private static func loadNOTES() throws -> String {
        try loadDocument("NOTES.md")
    }

    private static func loadDocument(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.append(path: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
