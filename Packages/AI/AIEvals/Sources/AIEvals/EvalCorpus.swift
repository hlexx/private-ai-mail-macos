import AIKit
import Foundation

/// A collection of 20 synthetic email threads covering diverse categories
/// for evaluating the AI thread brief feature. No real PII; shapes mirror DevSeeder.
public enum EvalCorpus {
    public static let threads: [(id: String, input: AIThreadInput)] = [
        // 1. Short informational — company newsletter
        ("eval-01-newsletter", AIThreadInput(messages: [
            .init(from: "updates@acmecorp.example", sentAt: d("2026-04-01T09:00:00Z"),
                  bodyText: "Hi team, Q1 results are in. Revenue up 12% YoY. Full report attached. No action needed."),
        ])),

        // 2. Single-action request — PTO approval
        ("eval-02-pto-request", AIThreadInput(messages: [
            .init(from: "jane.lee@example.com", sentAt: d("2026-04-02T10:30:00Z"),
                  bodyText: "Hi Manager, requesting PTO May 5-9. Coverage arranged with Tom. Please approve by April 18."),
        ])),

        // 3. Multi-message contract negotiation
        ("eval-03-contract-negotiation", AIThreadInput(messages: [
            .init(from: "legal@vendor.example", sentAt: d("2026-03-28T14:00:00Z"),
                  bodyText: "Attached is the revised MSA with updated indemnification clause (Section 7.2). Please review and return redlines by April 10."),
            .init(from: "alex@company.example", sentAt: d("2026-03-29T11:15:00Z"),
                  bodyText: "Thanks. Section 7.2 looks fine but we need the liability cap in Section 8.1 raised to $2M. Sending redlines today."),
            .init(from: "legal@vendor.example", sentAt: d("2026-04-01T09:30:00Z"),
                  bodyText: "We can agree to $1.5M cap. Final offer — please confirm by April 5 so we can close this quarter."),
        ], attachments: [
            .init(filename: "MSA_v3_redlined.pdf", mime: "application/pdf", pageCount: 24),
        ])),

        // 4. Attachment-heavy — design review
        ("eval-04-design-review", AIThreadInput(messages: [
            .init(from: "designer@studio.example", sentAt: d("2026-04-03T08:00:00Z"),
                  bodyText: "Hi team, attached are the final mockups for the dashboard redesign. 5 screens total. Please review and leave comments by Friday."),
        ], attachments: [
            .init(filename: "dashboard-home.fig", mime: "application/octet-stream"),
            .init(filename: "dashboard-analytics.fig", mime: "application/octet-stream"),
            .init(filename: "dashboard-settings.fig", mime: "application/octet-stream"),
            .init(filename: "dashboard-profile.fig", mime: "application/octet-stream"),
            .init(filename: "dashboard-notifications.fig", mime: "application/octet-stream"),
        ])),

        // 5. Calendar invite — team standup
        ("eval-05-calendar-invite", AIThreadInput(messages: [
            .init(from: "calendar@workspace.example", sentAt: d("2026-04-04T07:00:00Z"),
                  bodyText: "You have been invited to: Weekly Engineering Standup. When: Every Monday 10:00-10:15 AM. Where: Zoom (link in calendar). Organizer: Sarah Chen."),
        ])),

        // 6. Recruiting digest — candidate pipeline
        ("eval-06-recruiting-digest", AIThreadInput(messages: [
            .init(from: "recruiting@company.example", sentAt: d("2026-04-05T06:00:00Z"),
                  bodyText: "Weekly pipeline update: 3 new applications for Senior iOS role. 1 candidate (M. Torres) passed phone screen — schedule onsite by April 12. 2 candidates declined offer for Backend role."),
        ])),

        // 7. Financial / invoice
        ("eval-07-invoice", AIThreadInput(messages: [
            .init(from: "billing@cloudhost.example", sentAt: d("2026-04-01T00:00:00Z"),
                  bodyText: "Invoice #INV-2026-0401 for $4,250.00 is due April 15, 2026. Services: Cloud hosting (March). Payment terms: Net 15. Please remit to account ending in 7892."),
        ], attachments: [
            .init(filename: "INV-2026-0401.pdf", mime: "application/pdf", pageCount: 2),
        ])),

        // 8. Shipping notification
        ("eval-08-shipping", AIThreadInput(messages: [
            .init(from: "orders@supplier.example", sentAt: d("2026-04-06T12:00:00Z"),
                  bodyText: "Your order #ORD-88421 has shipped via FedEx. Tracking: 7948321654. Estimated delivery: April 9. 3 items: ergonomic keyboard, monitor arm, USB-C hub."),
        ])),

        // 9. Security alert
        ("eval-09-security-alert", AIThreadInput(messages: [
            .init(from: "security@company.example", sentAt: d("2026-04-07T03:15:00Z"),
                  bodyText: "ALERT: Unusual login detected on your account from IP 203.0.113.42 (São Paulo, Brazil) at 03:12 UTC. If this was not you, reset your password immediately and enable 2FA."),
        ])),

        // 10. Meeting follow-up with action items
        ("eval-10-meeting-followup", AIThreadInput(messages: [
            .init(from: "pm@company.example", sentAt: d("2026-04-07T16:00:00Z"),
                  bodyText: """
                  Meeting notes — Q2 Planning (Apr 7):
                  Attendees: Alex, Sarah, Tom, Priya
                  Decisions:
                  - Launch date moved to May 15
                  - Budget approved at $45K
                  Action items:
                  - Alex: finalize API spec by April 11
                  - Sarah: onboard QA contractor by April 14
                  - Tom: set up staging environment by April 10
                  Next meeting: April 14, 2:00 PM
                  """),
        ])),

        // 11. Support ticket escalation
        ("eval-11-support-escalation", AIThreadInput(messages: [
            .init(from: "support@saas.example", sentAt: d("2026-04-08T09:00:00Z"),
                  bodyText: "Ticket #SUP-4421 has been escalated to Tier 2. Customer reports data export failing for the past 48 hours. Error: timeout on /api/v2/export. SLA breach in 4 hours."),
            .init(from: "eng-oncall@saas.example", sentAt: d("2026-04-08T09:45:00Z"),
                  bodyText: "Investigating. Root cause: the export query hits a full table scan on the new audit_log table (200M rows). Deploying index fix now. ETA 30 minutes."),
        ])),

        // 12. Travel itinerary
        ("eval-12-travel", AIThreadInput(messages: [
            .init(from: "travel@bookings.example", sentAt: d("2026-04-09T10:00:00Z"),
                  bodyText: "Your trip to London is confirmed. Flight: BA117 JFK→LHR Apr 20 dep 19:00 arr Apr 21 07:10. Hotel: The Strand Palace, Apr 21-24. Return: BA178 LHR→JFK Apr 24 dep 11:30 arr 14:45. Booking ref: LNDN2026."),
        ])),

        // 13. PR review request
        ("eval-13-pr-review", AIThreadInput(messages: [
            .init(from: "github@notifications.example", sentAt: d("2026-04-10T14:00:00Z"),
                  bodyText: "tom-dev requested your review on PR #342: 'Add rate limiting to API gateway'. 12 files changed, +450 -30 lines. CI passing. Labels: security, backend."),
        ])),

        // 14. Subscription renewal
        ("eval-14-subscription-renewal", AIThreadInput(messages: [
            .init(from: "accounts@toolsuite.example", sentAt: d("2026-04-11T08:00:00Z"),
                  bodyText: "Your annual subscription (Team Plan, 25 seats) renews on May 1 for $12,500. To make changes (add/remove seats, switch plans, or cancel), update your account by April 25."),
        ])),

        // 15. Compliance / audit request
        ("eval-15-compliance", AIThreadInput(messages: [
            .init(from: "compliance@company.example", sentAt: d("2026-04-12T11:00:00Z"),
                  bodyText: "SOC 2 Type II audit: please provide evidence for Control CC6.1 (logical access) by April 19. Required: list of all admin accounts, last access review date, and MFA enrollment rate. Upload to the shared audit folder."),
        ], attachments: [
            .init(filename: "CC6.1_evidence_template.xlsx", mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", pageCount: nil),
        ])),

        // 16. Onboarding checklist
        ("eval-16-onboarding", AIThreadInput(messages: [
            .init(from: "hr@company.example", sentAt: d("2026-04-13T09:00:00Z"),
                  bodyText: "Welcome aboard! Your start date is April 28. Before day 1, please: (1) Complete I-9 form, (2) Set up direct deposit, (3) Upload a headshot for your badge. IT will send laptop shipping details separately."),
        ])),

        // 17. Outage notification
        ("eval-17-outage", AIThreadInput(messages: [
            .init(from: "status@platform.example", sentAt: d("2026-04-14T02:30:00Z"),
                  bodyText: "Incident: API latency spike affecting all regions. Started 02:15 UTC. Impact: 30% of requests returning 503. Team is investigating. We will post updates every 30 minutes."),
            .init(from: "status@platform.example", sentAt: d("2026-04-14T03:00:00Z"),
                  bodyText: "Update: Root cause identified — database failover triggered by disk full on primary. Promoting replica now. ETA to resolution: 15 minutes."),
            .init(from: "status@platform.example", sentAt: d("2026-04-14T03:20:00Z"),
                  bodyText: "Resolved: All systems operational. Total downtime: 65 minutes. Postmortem will be shared within 48 hours."),
        ])),

        // 18. Event invitation
        ("eval-18-event-invite", AIThreadInput(messages: [
            .init(from: "events@techconf.example", sentAt: d("2026-04-15T10:00:00Z"),
                  bodyText: "You're invited to TechConf 2026, June 12-14 in Austin, TX. Early bird registration ends May 1 ($599 vs $899). Use code SPEAKER25 for 25% off. RSVP required for the speaker dinner on June 12."),
        ])),

        // 19. Budget approval chain
        ("eval-19-budget-approval", AIThreadInput(messages: [
            .init(from: "finance@company.example", sentAt: d("2026-04-16T13:00:00Z"),
                  bodyText: "Budget request BR-2026-Q2-017 ($85,000 for infrastructure upgrade) requires VP approval. Current status: Director approved. Please approve or reject by April 20."),
            .init(from: "vp-eng@company.example", sentAt: d("2026-04-17T09:00:00Z"),
                  bodyText: "Approved. Please proceed with procurement. Ensure we get at least 3 vendor quotes before PO issuance per policy."),
        ])),

        // 20. Multi-thread project update
        ("eval-20-project-update", AIThreadInput(messages: [
            .init(from: "pm@company.example", sentAt: d("2026-04-18T08:00:00Z"),
                  bodyText: """
                  Project Phoenix — Week 3 Update:
                  Status: On track (green)
                  Completed: Database migration, auth service refactor
                  In progress: Frontend redesign (60%), API v3 endpoints (80%)
                  Blocked: CDN setup waiting on DNS delegation from ops team
                  Risks: QA capacity thin — may need to extend timeline if contractor onboarding delayed
                  Next milestone: Internal beta April 28
                  """),
        ])),
    ]

    private static func d(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("EvalCorpus: invalid ISO8601 date string: \(iso)")
        }
        return date
    }
}
