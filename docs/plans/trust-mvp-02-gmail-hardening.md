# Plan: Trust MVP 02 - Harden Gmail Baseline

## Summary

Bring Gmail to the Trust MVP bar before adding Outlook behavior. Gmail is the
reference implementation for the canonical provider contracts created in tranche
01. This tranche verifies and hardens labels/folders, mutations, send threading,
attachment fetch, HTML rendering, auth recovery, rate limits, offline states,
and privacy-safe observability. Do not add Microsoft Graph code here.

## Impact Checklist

- Business flow: daily Gmail reading, reply/send, archive/star/read/trash,
  attachment opening, and reconnect flows must be reliable.
- Domain boundaries: Gmail-specific behavior remains in `MailProviders/Gmail`
  and `MailSync`; feature modules use canonical mailbox and provider contracts.
- API / contracts: no public feature APIs should be removed; add small helper
  contracts only when needed to remove duplicate Gmail mutation logic.
- Schema / data model: no destructive migrations; label and attachment rows must
  survive normal refreshes.
- Auth / permissions: use existing Gmail scopes; missing scopes must trigger
  re-consent before mutation or send.
- Cache / queue / async workflow: sync should remain eventually consistent and
  rollback failed optimistic mutations.
- Observability: add privacy-safe logs for sync, mutation, send, attachment
  fetch, and auth failures; never log body, html, prompt, attachment bytes, or
  tokens.
- Migration: none expected unless a missing invariant requires additive state.
- Rollback: each hardening change should be separately revertible.
- Debt impact: retires Gmail demo/stub paths and weak error handling.
- ADR required: no new ADR if ADR 0005 already covers the contract; update ADR
  only if a new sync or mutation invariant is discovered.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/InboxFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ComposeFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ! /usr/bin/grep -R -n -E '(Bearer |refresh_token|client_secret|Logger.*(body|html|payload|attachment)|print\\(.*(body|html|payload|attachment))' Apps Packages --include='*.swift' --exclude-dir=.build --exclude='*Tests.swift'`

### Task 1: Audit Gmail UI actions end to end

- [ ] Trace archive, unarchive, star, unstar, read/unread, trash, untrash,
      send, refresh, attachment download, and reconnect from UI/store to Gmail
      API and local persistence.
- [ ] Create a short `docs/trust-mvp-gmail-baseline.md` table with each action,
      current code path, expected provider call, expected local state, expected
      user-visible failure, and test coverage.
- [ ] Replace any remaining no-op UI path for Gmail P0 actions with either a
      real handler or a disabled state with honest copy.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`.

### Task 2: Harden Gmail label and folder behavior

- [ ] Ensure `InboxStore` and sidebar filtering use canonical mailbox concepts
      while preserving Gmail label semantics.
- [ ] Add or extend tests for Inbox, Sent, Archive, Starred, Trash, Spam, Needs
      reply, Has deadline, and Has attachment filters where current code
      supports them.
- [ ] Verify archived Gmail threads do not appear in Inbox after a fresh sync or
      after label reconciliation.
- [ ] Verify label-only refresh does not delete unchanged attachments or AI
      artifacts.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/InboxFeature && swift test`.

### Task 3: Harden optimistic mutations and rollback

- [ ] Ensure every Gmail mutation resolves a real provider client before local
      optimistic mutation.
- [ ] For archive/star/read/trash operations, add tests for provider failure,
      missing credential, rate limit, repeated operation, and local rollback.
- [ ] Ensure user-visible errors distinguish missing credential, insufficient
      scope, rate limit, offline, and provider rejection.
- [ ] Add privacy-safe logs keyed by account id/thread id or stable hashes only.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`.

### Task 4: Harden Gmail send and threading

- [ ] Verify `ComposeService` builds RFC-compliant `In-Reply-To` and
      `References` headers for replies and passes the Gmail `threadId`.
- [ ] Add tests for new message send, reply send, missing recipients,
      insufficient `gmail.send` scope, API failure, and local sent-record
      insertion.
- [ ] Prevent duplicate local sent rows if Gmail returns the same sent message
      again through incremental sync.
- [ ] Ensure failed sends are visible to the user and do not look sent locally.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ComposeFeature && swift test`.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`.

### Task 5: Harden Gmail attachment and HTML basics

- [ ] Verify attachment metadata, inline CID attachments, remote-image blocking,
      attachment byte download, unsupported states, and local byte cache paths.
- [ ] Add tests for attachment download failure, unsupported attachment
      extraction, missing attachment id, and no raw attachment content in logs.
- [ ] Ensure HTML rendering remains tracker-safe by default and has a clear
      blocked-remote-content state.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`.

### Task 6: Validate Gmail privacy and release readiness

- [ ] Run the privacy grep command from Validation Commands and fix any real
      leaks. Do not silence it by removing useful privacy-safe logs.
- [ ] Add or update a manual Gmail smoke checklist under `docs/` covering fresh
      sync, search placeholder state, send, reply, archive, star, read/unread,
      trash, attachment open, HTML remote image blocking, offline open, auth
      expiry, and rate limit.
- [ ] Run all validation commands listed above and fix failures.

## Rollback / Recovery

If a Gmail hardening change blocks release, revert that action path and leave
the UI disabled rather than shipping a misleading control. Do not revert
provider-neutral contracts from tranche 01 unless they are the direct failure.

