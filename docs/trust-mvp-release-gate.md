# Trust MVP Release Gate

This document defines the release gate for the Gmail and Outlook Trust MVP.
The product is not release-ready until the automated checks and the manual
real-account smoke checks below pass on the same release candidate, or every
remaining blocker has an owner and an explicit fix decision.

The gate verifies existing product behavior. It does not create new product
scope, provider scope, or telemetry exceptions.

## Scope and Trust Boundary

The Trust MVP release candidate covers Gmail API and Microsoft Graph/Outlook
mail workflows only. The core user outcome is that a user can connect a real
mail account, sync it, search it locally, act on messages, send mail, open
cached content offline, recover from expected provider failures, and trust that
mailbox content is not mirrored outside the device or connected provider.

The local-first boundary from ADR 0005 remains mandatory:

- Raw message bodies, rendered HTML, snippets, attachments, drafts, local search
  indexes, AI artifacts, prompts, provider cursors, and raw provider responses
  stay on the Mac unless the user explicitly sends mail or approves a documented
  external payload.
- Provider calls are limited to user-authorized Gmail or Microsoft Graph sync,
  mutation, attachment fetch, send, token refresh, and re-consent workflows.
- Diagnostics may record privacy-safe metadata such as provider, operation,
  local account id or account hash, status, duration, retry count, checkpoint
  state category, and shared error category. Diagnostics must not include raw
  mailbox content, secrets, provider URLs with embedded state, or search query
  text.

## Automated Acceptance Criteria

All automated checks must be runnable from the release gate script or from the
documented full release command. Fixture data must be synthetic or minimized and
must not contain real tokens, raw private mail, provider secrets, or copied
customer content.

Default local gate:

```bash
./scripts/verify-trust-mvp.sh
```

Full release gate, including Tuist generation and the Debug macOS app build:

```bash
FULL_TRUST_MVP_GATE=1 ./scripts/verify-trust-mvp.sh
```

Temporary SwiftLint baseline:

- Why necessary now: when the gate script was introduced, strict SwiftLint had
  pre-existing size, nesting, and type-body violations across UI, sync,
  persistence, search, and attachment modules.
- Why the structural fix is not in this task: reducing those violations safely
  requires cross-module refactors outside the release-gate script boundary.
- Owner: Trust MVP release owner.
- Expiry: remove the baseline by 2026-06-30 or before promoting the Trust MVP
  beyond internal/beta release, whichever comes first.
- Removal plan: refactor baseline-listed files, regenerate the baseline until
  it is empty, remove `baseline: .swiftlint-baseline.json` from
  `.swiftlint.yml`, and rerun `swiftlint --strict --reporter xcode`.
- Rollback plan: if the baseline hides a new lint regression, delete the
  matching stale baseline entry and rerun the gate; do not loosen rule
  thresholds.

| Area | Required automated criteria | Evidence |
| --- | --- | --- |
| Gmail provider flow | Gmail fixtures cover labels, history checkpoints, messages, recipients, bodies, attachments, send responses, mutation responses, auth failures, rate limits, and not-found cases. Mapper and client tests prove Gmail data maps into shared mailbox, search, send, attachment, and error contracts without leaking Gmail DTOs across provider boundaries. | MailProviders and MailSync test results, fixture review, privacy grep. |
| Microsoft Graph provider flow | Graph fixtures cover folders, per-folder delta pages, messages, recipients, categories, flagged state, attachments, send responses, mutation responses, auth failures, throttling, and opaque next/delta links. Tests prove Graph data maps into the same canonical contracts where Graph and Gmail capabilities overlap. | MailProviders and MailSync test results, fixture review, privacy grep. |
| Search | Local index tests cover indexed thread/message fields, provider-neutral mailbox state, attachment metadata markers, FTS migrations, empty and no-result states, and provider-overlap queries. Search must not depend on Gmail labels or Graph folders outside the mapping boundary. | MailIndex test results and migration test results. |
| Send queue | Compose and queue tests cover draft creation, queue persistence, idempotency keys, send success, retryable failures, permanent failures, offline recovery, rate-limit retry scheduling, auth re-consent state, reply threading, and no local sent row before provider success. | ComposeFeature, MailDomain, Persistence, and provider send test results. |
| Attachment baseline | Attachment tests cover metadata mapping, byte fetch, local byte cache, cache deletion, preview state resolution, unsupported types, missing/deleted cache files, inline CID behavior where supported, extraction boundaries, and AI summary evidence requirements. Outlook attachment download/preview can pass only if Graph byte-provider wiring is end-to-end; otherwise the blocker must be documented. | AttachmentKit, AttachmentRAG, MailProviders, ThreadFeature, and Persistence test results. |
| Privacy and observability | Privacy grep rejects access tokens, refresh tokens, bearer headers, client secrets, raw bodies, HTML payloads, raw prompts, model outputs, raw attachment bytes, raw provider payloads, Graph delta URLs, Gmail history payload dumps, unsafe logger fields, and unsafe print statements in non-test Swift code. Structured logs cover provider, account hash or local account id, operation, stage, status, retry count, checkpoint category, and shared error category. | Verification script output and spot review of changed logging call sites. |
| Migrations and deletion | Persistence tests cover fresh database creation, upgrade-style migration with seeded Gmail data, Outlook-compatible account rows, Graph checkpoint rows where present, account deletion cascade for messages, labels or folders, attachments, search index rows, drafts, send queue rows, and AI artifacts. | PersistenceTests output. |
| App build | Tuist generation and Debug macOS app build pass with code signing disabled. SwiftLint strict mode passes. Whitespace checks pass. | `tuist generate --no-open`, `xcodebuild build`, `swiftlint --strict --reporter xcode`, and `git diff --check` output. |

## Feature Rollback Behavior

Rollback must preserve local data and privacy boundaries. Disabling a gated
Trust MVP area is allowed only when the user-visible product state stays honest,
existing local rows remain recoverable, and Gmail-stable workflows are not
silently changed.

| Feature area | Required rollback behavior |
| --- | --- |
| Microsoft Graph / Outlook | Disable Outlook connection, sync, mutation, send, and attachment-fetch entry points through the release-candidate flag or build configuration. Keep additive Outlook schema, existing `outlook` account rows, folder labels, and `graph_delta_checkpoint` rows intact so re-enabling can resume from provider checkpoints. Gmail runtime paths must continue to work. Do not delete Outlook data as part of a feature rollback; account deletion remains the only destructive user action. |
| Local search | Disable search UI execution and background index rebuild scheduling if the search gate blocks release. Keep `mail_search_document`, `mail_search_fts`, and rebuild metadata tables on disk. Mark the index as needing rebuild before re-enabling. Do not fall back silently to provider/server search, and do not log local query text while search is disabled. |
| Send queue | Disable the queue executor or provider send adapter while keeping draft and `send_queue_item` rows visible with pending, retry, failed, canceled, or needs-consent state. Re-enabling must continue through existing idempotency keys. Do not auto-send retained rows during rollback, and do not delete queued mail unless the user explicitly cancels it. |
| Attachment preview | Disable preview and byte-download controls if preview or byte-cache validation blocks release. Keep attachment metadata, cached blob records, extraction rows, chunks, and AI artifacts local. Re-enabling must validate cached files before previewing them. Do not start provider byte fetches in the background as a rollback fallback. |
| Privacy telemetry | Disable any telemetry export path that cannot pass the privacy grep or event contract review. Keep local status, error categories, and privacy UI available with privacy-safe metadata only. Re-enabling requires the gate to prove no raw mailbox content, prompts, provider payloads, tokens, attachment bytes, local index contents, or query text leave the device. |

## Manual Gmail Smoke Criteria

Run this checklist against a real non-production Gmail account on the same
release candidate that passed the automated gate. Record only the commit SHA,
app version, account id hash, thread/message/attachment id hashes, timestamps,
visible state, counts, and shared error categories.

| Area | Required manual behavior |
| --- | --- |
| Connect | A fresh Gmail account can be connected from the product UI with the expected OAuth scopes. The UI shows a connected account without requiring credentials to be pasted into notes or logs. |
| Initial sync | Initial sync completes with Inbox, labels, thread list, messages, snippets/previews, unread state, starred state, sent state, trash state, and attachment metadata visible without duplicate threads. |
| Refresh | Manual refresh and incremental provider sync reconcile new mail, label changes, read/unread changes, sent messages, deleted/trash state, and attachment metadata without resetting unrelated local state. |
| Search | Local search returns expected synced messages for representative sender, subject, body, mailbox, and attachment-metadata queries. Empty results are explicit. Query text is not logged. |
| Send and reply | New send and reply succeed only after user approval and provider success. Replies remain in the expected Gmail thread. Failed sends stay visible with retry or reauthorize state and no false sent row. |
| Archive | Archiving an Inbox thread removes it from Inbox locally and after refresh. Undo or restore behavior returns the expected state where supported. |
| Read and unread | Mark read and mark unread update visible unread state locally and remain correct after refresh. |
| Star | Star and unstar update visible starred state locally and remain correct after refresh. |
| Trash | Moving a thread to Trash updates visible state locally and after refresh. Restore or undo returns the expected state where supported. |
| Attachment download and preview | Attachment metadata is visible. Byte download occurs only through a user-visible action. Supported cached files preview locally. Unsupported, failed, missing, or metadata-only states are explicit. |
| Offline open | With the network disabled, already-synced thread content opens from local storage. Provider-required actions fail visibly, stay queued, or remain disabled without silent success. |
| Re-consent | Removing or expiring credentials leads to a visible reconnect or reauthorize path. Sync or send resumes after re-consent without losing local account data. |
| Rate-limit and error visibility | Simulated or real throttling, provider errors, and transient network failures surface a visible shared error category and preserve rollback or retry behavior. |

## Manual Outlook Smoke Criteria

Run this checklist against a real non-production Outlook or Microsoft 365
mailbox on the same release candidate that passed the automated gate. Record
only the commit SHA, app version, account id hash, folder/thread/message/
attachment id hashes, timestamps, visible state, counts, and shared error
categories. If Outlook remains feature-gated, this checklist must be run with
the documented release-candidate flag state.

| Area | Required manual behavior |
| --- | --- |
| Connect | A fresh Outlook account can be connected from the product UI with delegated Microsoft Graph scopes limited to the Trust MVP. The UI shows a connected account without exposing tokens, tenant secrets, or raw provider URLs. |
| Initial sync | Initial sync completes for the selected folder set with folders, messages, categories where visible, flagged state, read/unread state, sent state, trash/deleted state, and attachment metadata visible without duplicate messages. |
| Refresh | Manual refresh and per-folder delta sync reconcile new mail, folder moves, category or flag changes, read/unread changes, sent messages, deleted/trash state, and attachment metadata while preserving opaque Graph delta links. |
| Search | Local search returns expected synced messages for representative sender, subject, body, mailbox/folder, and attachment-metadata queries. Empty results are explicit. Query text is not logged. |
| Send and reply | New send and reply succeed only after user approval and provider success. Replies remain associated with the expected conversation where Graph supplies enough data. Failed sends stay visible with retry or reauthorize state and no false sent row. |
| Archive | Archive or provider-equivalent folder movement updates visible state locally and after refresh. If the account lacks a provider archive convention, the UI must make the unsupported state explicit. |
| Read and unread | Mark read and mark unread update visible state locally and remain correct after refresh. |
| Flag | Flag and unflag update visible flagged state locally and remain correct after refresh. The UI must not represent Graph flagged state as Gmail starred semantics outside the canonical display contract. |
| Trash | Moving a message to Deleted Items or Trash updates visible state locally and after refresh. Restore or undo returns the expected state where supported. |
| Attachment download and preview | Attachment metadata is visible. Byte download occurs only through a user-visible action. Supported cached files preview locally. Unsupported, failed, missing, or metadata-only states are explicit. If Outlook attachment bytes are not wired end-to-end, this is a release blocker or documented beta limitation with owner. |
| Offline open | With the network disabled, already-synced message content opens from local storage. Provider-required actions fail visibly, stay queued, or remain disabled without silent success. |
| Re-consent | Removing or expiring credentials leads to a visible reconnect or reauthorize path. Sync or send resumes after re-consent without losing local account data or provider checkpoints. |
| Rate-limit and error visibility | Simulated or real throttling, provider errors, and transient network failures surface a visible shared error category and preserve rollback or retry behavior. Graph retry-after handling must not log raw provider payloads or opaque delta URLs. |

## Non-Goals

Passing this release gate does not certify or imply support for:

- iCloud Mail, IMAP, JMAP, or any provider outside Gmail API and Microsoft
  Graph/Outlook.
- Shared mailboxes, delegated mailboxes, team inboxes, application-permission
  mailbox access, tenant administration, or enterprise governance UI.
- CRM writes or CRM synchronization.
- Slack writes, Notion writes, or any external workflow write-back.
- Send later, scheduled send, auto-send, or autonomous outbound mail.
- Mobile companion apps.
- Broad attachment OCR, DOCX extraction, archive extraction, or arbitrary file
  preview beyond the attachment baseline that is actually tested.
- Cloud AI fallback or cloud telemetry containing mailbox content, drafts,
  attachment bytes, local indexes, prompts, model outputs, or provider payloads.

## Gate Run Evidence - 2026-05-31

Date: 2026-05-31 15:23:35 +05

Base commit SHA at Task 6 validation start: `f60865505288`

Context:

- Machine/local context: macOS local developer machine, Xcode 26.2.0, Tuist,
  SwiftLint, SwiftPM package tests, and Debug macOS app build.
- Task 6 worktree note: the gate run included a deterministic wait fix in
  `Packages/Features/InboxFeature/Tests/InboxFeatureTests/ChipFilterTests.swift`.
  The first `./scripts/verify-trust-mvp.sh` attempt exposed a flaky fixed sleep
  in `folderCountsIncludeBriefDrivenCounts`; the test now waits for observed
  `needsReply` and `hasDeadline` folder counts before asserting.
- Feature flag state: no runtime feature flag change was made in this evidence
  pass. Graph/Outlook, search, send queue, attachment preview, attachment
  summarization, and privacy telemetry remain governed by their existing
  release-candidate behavior and documented rollback rules.

Automated command outcomes:

| Command | Outcome | Evidence |
| --- | --- | --- |
| `git status --short --branch` | Passed | Reported branch `trust-mvp-07-privacy-ui-observability` and no uncommitted changes at the start of Task 6 validation. |
| `git diff --check` | Passed | No whitespace errors. |
| `./scripts/verify-trust-mvp.sh` | Passed | Default gate passed repository hygiene, SwiftLint, package tests, and privacy grep. Package suites passed: MailDomain 15 tests, MailProviders 61, MailSync 35, MailIndex 20, Persistence 60, AuthKit 30, ComposeFeature 58, InboxFeature 45, ThreadFeature 67, SettingsFeature 28, AttachmentKit 11, AttachmentRAG 11. Default mode intentionally skipped Tuist/xcodebuild and printed the full release command. |
| `swiftlint --strict --reporter xcode` | Passed | Linted 221 Swift files with 0 violations and 0 serious violations. |
| `tuist generate --no-open` | Passed | Generated `PrivateAIMail.xcworkspace` successfully. Xcode emitted a supported-platform warning during package resolution, but Tuist exited 0. |
| `xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` | Passed | Debug macOS app build completed with `** BUILD SUCCEEDED **`. Xcode selected the arm64 `My Mac` destination and noted signing/hardened-runtime behavior because code signing was disabled for the gate. |

Manual steps remaining:

- Real Gmail smoke checklist from this document must still be run against a
  non-production Gmail account before release signoff. Owner: Trust MVP release
  owner.
- Real Outlook or Microsoft 365 smoke checklist from this document must still
  be run against a non-production mailbox, with the documented release-candidate
  Graph/Outlook flag state. Owner: Trust MVP release owner.
- Manual evidence must record only commit SHA, app version, account/message/
  thread/attachment hashes, timestamps, visible state, counts, and shared error
  categories.

Blockers:

- No automated release-gate blockers remained after the InboxFeature observation
  wait fix and full rerun.

## Evidence and Failure Handling

The release gate evidence must include:

- Date, commit SHA, app version, machine or CI context, and command outcomes.
- Manual smoke tester, provider, account hash, counts, timestamps, visible
  states, and shared error categories only.
- Exact blockers, owners, and required fixes for any failed or skipped gate.
- Feature flag state for Graph, search, send queue, attachment preview,
  attachment summarization, and privacy telemetry.

Do not weaken or delete a gate because it is slow or inconvenient. If a gate is
too expensive for the default local loop, keep the default check for privacy,
provider contracts, migrations, and package tests, then put the slower app build
or live-account step behind an explicit full-gate command with an owner and
expiry for any temporary manual workaround.
