# ADR 0002: Private Inbox, Attachment Intelligence, Team Connect Sequencing

Status: Accepted

Date: 2026-05-22

## Context

The next development tranche touches three related but distinct product
capabilities:

1. the Private AI inbox baseline;
2. attachment intelligence;
3. Team Connect integrations.

These capabilities share user-facing surfaces, AI artifacts, persistence, and
future workflow actions. Building the Team Connect path before inbox state and
attachment extraction are observable would blur trust boundaries and create
integration payloads that cannot be explained, audited, or retried safely.

The source-of-truth product and security docs define the required sequence as:

```text
Private AI inbox
  -> attachment intelligence
  -> Slack/Notion workflow
  -> HubSpot CRM
  -> Salesforce/Enterprise
```

## Decision

This tranche will preserve the sequence below:

1. Private AI inbox first.
2. Attachment Intelligence second.
3. Team Connect integrations third.

No Slack, Notion, CRM, or other SaaS write path may be wired until the app has
real inbox state, attachment extraction, minimized action payloads, explicit
approval state, retry status, and idempotency keys that are observable and
testable.

Team Connect work in this tranche is limited to typed proposal, preview,
approval, status, and dispatch contracts. Connector behavior must remain behind
an explicit user-approved boundary and may use preview-only stubs until the
broker deployment and connector ownership model are ready.

## Trust Boundary

The EMAIL_ALF trust boundary is mandatory:

- raw email bodies stay on device;
- attachments stay on device;
- semantic indexes stay on device;
- AI artifacts stay on device;
- reply drafts stay on device.

Team Connect may send only user-approved minimized payloads to the connector
broker and target SaaS. A minimized payload may include a summary, deadline,
next step, entity mapping, Slack message content, Notion page content, or later
CRM note content only after the user has seen what will leave the device and
approved the action or an explicit approved rule.

The app must not log raw email bodies, attachment bytes, semantic index content,
bearer tokens, refresh tokens, or full generated external payloads.

## Non-goals

The following are outside this tranche:

- SQLCipher or SQLite page encryption;
- CRM writes;
- Salesforce integration;
- enterprise governance, SSO, SCIM, or admin policy controls;
- multi-device sync;
- auto-send or automatic external writes without explicit user approval.

FileStore/encrypted-at-rest work for attachment bytes remains in scope because
attachments are device-local sensitive data and are not a SQLCipher substitute.

## Options Considered

### Option A: Build Team Connect first

This could expose paid workflow value early, but it would depend on incomplete
attachment extraction and unclear action provenance. It would also create a
high-risk external payload path before minimized payloads, approval state,
retry behavior, and idempotency are modeled.

### Option B: Build attachment intelligence before hardening inbox actions

This would advance the document-understanding surface, but attachment
processing depends on stable account, message, attachment, and local storage
state. If mailbox actions are still demo-only or locally optimistic before
provider validation, attachment jobs and summaries can drift from provider
truth.

### Option C: Sequence inbox, attachment intelligence, then Team Connect

This preserves the product roadmap and trust model. It makes provider-backed
mailbox state the foundation, makes attachment extraction evidence-backed, and
then lets Team Connect consume typed minimized payloads with explicit approval
and status.

## Consequences

Chosen approach: Option C.

The app may show disabled or preview-only Team Connect affordances while the
underlying contracts are being built, but it must not imply external writes are
available before the broker and connector paths are real. Attachment summaries
must be evidence-backed, and incomplete or unsupported extraction must be shown
as such instead of treated as a successful empty result.

This decision retires the ambiguity around attachment and integration namespace
stubs. It introduces deliberate integration preview stubs only where they
preserve the future production boundary and are clearly not live SaaS writes.

## Validation

Each tranche must validate the boundary it introduces:

- inbox work: provider-backed mutations, rollback on provider failure, and
  privacy-safe mutation logs;
- attachment work: additive persistence migrations, FileStore policy,
  evidence-backed extraction, incomplete-state handling, and local summary
  cache invalidation;
- Team Connect work: typed minimized proposals, approval state, idempotency
  keys, status/audit metadata, and no SaaS writes without explicit approval.

Documentation, tests, and privacy-grep checks must remain aligned with this ADR
before enabling the next layer in the sequence.

## Rollback

If a later step proves unsafe, disable the new attachment processing or Team
Connect dispatch from composition/feature flags and leave additive persistence
tables unused. Do not drop newly added tables as part of rollback. Any
preview-only connector stub can be removed without changing the inbox or
attachment contracts.

## Documentation Audit

The current README and NOTES files do not claim that attachment intelligence or
Team Connect integrations are already complete. They therefore do not need a
capability-status correction for this ADR.
