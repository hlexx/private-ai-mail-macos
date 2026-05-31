# Plan: Trust MVP 01 - Gmail and Outlook Provider Contracts

## Summary

Create the architecture gate for a Gmail + Outlook Trust MVP before adding more
provider code. The goal is to make the app's mail model provider-neutral enough
for Gmail API and Microsoft Graph without weakening the current local-first
privacy boundary. This tranche records the ADR, removes Gmail-only assumptions
from shared contracts, and defines explicit sync, mutation, send, search,
attachment, error, and observability contracts. Do not implement Microsoft Graph
network calls in this tranche.

## Impact Checklist

- Business flow: account connection, mailbox reading, search, message send,
  offline use, and provider error recovery become Trust MVP gates.
- Domain boundaries: `MailDomain` owns canonical provider-neutral types;
  `MailProviders` owns Gmail and Graph adapter protocols; `MailSync` owns sync
  orchestration; feature modules must not branch on provider implementation
  details.
- API / contracts: add or refine shared provider contracts for message fetch,
  folder/label mapping, mutations, send, attachment fetch, and sync checkpoints.
- Schema / data model: allow provider values beyond `gmail`; add migration only
  if existing database constraints block Outlook accounts.
- Auth / permissions: document Gmail scopes and Microsoft Graph delegated scopes,
  but do not add new OAuth flows yet.
- Cache / queue / async workflow: define checkpoint semantics for Gmail History
  and Graph delta links; no new background workers in this tranche.
- Observability: define privacy-safe log fields and error taxonomy for sync,
  send, mutation, search, attachment fetch, and auth.
- Migration: additive or data-preserving only; existing Gmail rows must remain
  readable without reauth.
- Rollback: keep new contracts source-compatible where possible; any schema
  migration can remain dormant if Graph is disabled.
- Debt impact: retires Gmail-only assumptions in shared layers and docs
  overclaim; introduces no temporary workaround.
- ADR required: yes. This is the root architecture decision for the Trust MVP.

## Validation Commands

- Run SwiftPM validation on native arm64 only. Do not add `--arch x86_64` in
  this environment; Xcode 26.2 Swift Testing helper can hang uninterruptibly
  under the x86_64 path.

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailDomain && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && swiftlint --strict --reporter xcode`

### Task 1: Record ADR 0005 for the Trust MVP boundary

- [x] Create `docs/adr/0005-trust-mvp-gmail-outlook-provider-contracts.md`.
- [x] State the Trust MVP scope: Gmail API and Microsoft Graph only; no
      iCloud, IMAP, JMAP, shared mailboxes, delegated mailboxes, team inbox,
      CRM writes, Slack/Notion writes, or auto-send in this tranche.
- [x] State the product order: reliable sync/search/send/offline/error recovery
      first, optional private AI second.
- [x] State the local-first boundary: raw bodies, attachments, drafts, local
      indexes, AI artifacts, and model prompts stay on device unless the user
      explicitly sends mail or approves a minimized external payload.
- [x] State provider checkpoint rules: Gmail uses History API checkpoints;
      Graph uses per-folder opaque delta URLs. UI and feature modules must not
      inspect those provider-specific checkpoint payloads.
- [x] Include rollback: Graph remains behind a feature flag and dormant schema
      fields can stay unused if Outlook blocks release.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`.

### Task 2: Audit and name the current Gmail-only assumptions

- [x] Inspect `Packages/Mail/MailDomain`, `Packages/Mail/MailProviders`,
      `Packages/Mail/MailSync`, `Packages/Core/Persistence`,
      `Packages/Auth/AuthKit`, `Apps/MacApp/Sources/CompositionRoot.swift`,
      and feature stores for hard-coded `gmail`, Gmail label IDs, Gmail errors,
      and direct `GmailAPI` references crossing shared boundaries.
- [x] Add a short checklist section to the ADR listing the assumptions that are
      intentionally kept in Gmail-specific adapters.
- [x] Add focused TODO comments only where a shared layer still has a provider
      leak that cannot be removed safely in this tranche.
- [x] Do not add comments in UI files unless the code path is genuinely
      provider-specific and actionable.

### Task 3: Add canonical provider identifiers and mailbox vocabulary

- [x] Add a provider-neutral type in `MailDomain` or `MailProviders` for
      supported providers: Gmail and Microsoft Graph/Outlook. Preserve string
      compatibility with existing account records.
- [x] Add canonical mailbox concepts for inbox, sent, drafts, trash, spam,
      archive/all-mail where representable, starred/flagged, and user-defined
      labels/categories.
- [x] Document Gmail mapping: labels are many-to-many, archive means no `INBOX`
      label, starred maps to `STARRED`, sent maps to `SENT`.
- [x] Document Graph mapping: folders are hierarchical, categories are
      user-defined metadata, flagged is not the same as Gmail `STARRED`, and
      archive is a folder/move behavior, not a missing label.
- [x] Add unit tests for provider identifier and canonical mailbox mapping
      round trips.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailDomain && swift test`.

### Task 4: Define shared provider error and capability contracts

- [x] Add or update shared types for provider capabilities: supports labels,
      supports folders, supports categories, supports send, supports attachment
      download, supports delta sync, supports server search, supports aliases.
- [x] Add shared provider error categories: missing credential, insufficient
      scope, auth expired, rate limited, offline, provider unavailable,
      not found, invalid response, unsupported operation, and conflict.
- [x] Map existing `GmailAPIError` into the shared taxonomy without deleting
      Gmail-specific error details.
- [x] Add tests that Gmail errors map to user-actionable shared categories.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`.

### Task 5: Make persistence compatible with Outlook account rows

- [x] Inspect the `account.provider` schema constraint in the initial migration
      and the live `AccountRecord` contract.
- [x] If the schema still restricts provider to only `gmail`, add a
      data-preserving migration that allows at least `gmail` and `outlook`.
- [x] Keep existing Gmail accounts unchanged and prove existing fixtures or
      tests still pass.
- [x] Add `PersistenceTests` covering Gmail and Outlook account insert/fetch,
      duplicate `(provider, email)` uniqueness, and cascade behavior.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`.

### Task 6: Add the implementation sequencing document

- [x] Add `docs/trust-mvp-sequencing.md` or update `NOTES.md` with the eight
      Trust MVP tranches and their release gates.
- [x] Mark Microsoft Graph, full local search, send queue, and broad attachment
      preview as planned or in progress unless implemented in code.
- [x] Avoid editing `../EMAIL_ALF` from this app plan. If product docs need
      follow-up, add a note naming the exact EMAIL_ALF files to update later.
- [x] Run all validation commands listed above and fix failures.

## Rollback / Recovery

If contract changes destabilize the app, revert this tranche before running
later Trust MVP plans. If only the provider schema migration ships, keep it:
allowing the extra provider value is backwards-compatible while Graph remains
feature-gated.
