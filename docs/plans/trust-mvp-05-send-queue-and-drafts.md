# Plan: Trust MVP 05 - Send Queue and Draft Reliability

## Summary

Move send reliability from a direct composer-to-provider call into a durable
local send queue and draft model. Trust MVP must make pending, sent, failed,
retryable, duplicate, offline, and insufficient-scope states explicit for Gmail
and Outlook. This tranche does not add send later or AI auto-send.

## Impact Checklist

- Business flow: composing, saving, sending, retrying, and understanding send
  failures become reliable daily email workflows.
- Domain boundaries: `ComposeFeature` owns editing UX; `MailDomain` owns draft
  and outgoing message contracts; `Persistence` owns queue state; providers own
  send execution.
- API / contracts: add `SendQueue`, `DraftStore`, `QueuedSend`, and provider
  send result contracts.
- Schema / data model: additive draft and send queue tables; existing sent
  message records remain compatible.
- Auth / permissions: provider send scopes must be checked before execution;
  re-consent surfaces before retry.
- Cache / queue / async workflow: local queue supports pending, sending, sent,
  failed, retry scheduled, canceled, and duplicate-protected states.
- Observability: privacy-safe logs for state transitions and provider errors;
  never log body, HTML, recipients beyond redacted addresses, tokens, or raw MIME.
- Migration: additive only; rollback can leave queue tables dormant.
- Rollback: disable queued send executor and keep direct send only if tests prove
  safe; prefer disabling send UI over duplicate sends.
- Debt impact: retires direct-send fragility and creates the base for send later.
- ADR required: update ADR 0005 if queue semantics are not already covered.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailDomain && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ComposeFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ! /usr/bin/grep -R -n -E '(Logger.*(body|html|mime|payload)|print\\(.*(body|html|mime|payload)|Bearer |refresh_token|client_secret)' Apps Packages --include='*.swift' --exclude-dir=.build --exclude='*Tests.swift'`

### Task 1: Record queue semantics

- [ ] Update ADR 0005 or add a focused send queue section to
      `docs/trust-mvp-sequencing.md`.
- [ ] Define queue states, retry policy, idempotency key, duplicate prevention,
      user cancellation, offline behavior, insufficient-scope behavior, and
      provider reconciliation after send.
- [ ] State non-goals: send later, background delivery while app is quit, AI
      auto-send, shared mailbox send-as, and enterprise delegated send.

### Task 2: Add domain and persistence models

- [ ] Add domain types for draft identity, queued outgoing message, send queue
      status, retry policy, provider send result, and sanitized failure.
- [ ] Add additive persistence tables for drafts and send queue items with
      provider, account id, message ids, thread id, RFC header ids,
      idempotency key, status, attempts, created/updated/sent timestamps, and
      sanitized error fields.
- [ ] Keep body storage local and document whether it is stored in SQLite or a
      local file store. Do not introduce cloud draft storage.
- [ ] Add tests for migrations, draft save/fetch/delete, queue insert/fetch,
      idempotency uniqueness, account cascade, and retry metadata.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailDomain && swift test`.

### Task 3: Build provider-neutral send execution

- [ ] Extract send execution so Gmail and Graph can implement a shared provider
      send contract while preserving Gmail MIME builder behavior.
- [ ] Map provider errors into shared send failure categories.
- [ ] Add tests for Gmail send success/failure and Graph send test doubles if
      Graph adapter exists from tranche 03.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`.

### Task 4: Implement SendQueue service

- [ ] Add a `SendQueueService` or actor that enqueues drafts, executes the next
      eligible item, marks success/failure, schedules retry, and prevents
      duplicate execution for the same idempotency key.
- [ ] Ensure the executor checks credentials/scopes before sending and fails
      without mutating local sent state if credentials are missing.
- [ ] Insert or reconcile the local sent message only after provider success.
- [ ] Add tests for offline, provider failure, rate limit retry, duplicate
      enqueue, duplicate provider success, cancellation, and app restart fetch.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ComposeFeature && swift test`.

### Task 5: Wire composer UX to queue states

- [ ] Update full compose and inline compose flows to enqueue and show pending,
      sending, sent, failed, retrying, and needs re-consent states.
- [ ] Ensure user cannot accidentally click Send twice and produce duplicate
      provider sends.
- [ ] Keep manual retry explicit for non-transient failures.
- [ ] Add tests for disabled send button during sending, retry action, failure
      display, and no duplicate local sent rows.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ComposeFeature && swift test`.
- [ ] Run all validation commands listed above and fix failures.

## Rollback / Recovery

If queue execution is unsafe, disable send execution and leave drafts editable.
Never ship a known duplicate-send path. Queue tables can remain dormant.

