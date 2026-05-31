# Plan: Trust MVP 07 - Privacy UI and Observability

## Summary

Make the trust model visible and operational. Users should understand what stays
local, what is sent to Gmail or Microsoft Graph, what is never mirrored to the
app's cloud, and how AI/cloud fallback is controlled. Engineers should have
privacy-safe observability for sync, search, send, attachments, and auth without
logging raw mail content.

## Impact Checklist

- Business flow: users connect work accounts only if privacy and failure states
  are clear.
- Domain boundaries: Settings/Privacy displays policy; services emit sanitized
  events; no feature module logs raw content.
- API / contracts: add privacy status/read model and sanitized observability
  event contracts if missing.
- Schema / data model: no raw-content telemetry tables; local settings may store
  privacy preferences additively.
- Auth / permissions: show provider scopes and connected-account permission
  states; no new scopes.
- Cache / queue / async workflow: expose local cache and AI state without
  sending content externally.
- Observability: OSLog categories and optional metrics must be content-free.
- Migration: optional additive user preference keys only.
- Rollback: disable telemetry export and keep local UI static if needed.
- Debt impact: retires vague privacy copy and ad hoc logging.
- ADR required: update ADR 0005 if telemetry leaves device.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/SettingsFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/AppFoundation && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ComposeFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ! /usr/bin/grep -R -n -E '(Logger.*(body|html|payload|prompt|model|attachment)|os_log.*(body|html|payload|prompt|model|attachment)|print\\(.*(body|html|payload|prompt|model|attachment)|Bearer |refresh_token|client_secret)' Apps Packages --include='*.swift' --exclude-dir=.build --exclude='*Tests.swift'`

### Task 1: Define privacy status copy and data classes

- [x] Add `docs/trust-mvp-privacy-and-observability.md` with data classes:
      local raw mail, local attachments, local drafts, local indexes, local AI
      artifacts, provider API requests, optional cloud/control-plane metadata,
      and approved external payloads.
- [x] State "no mailbox mirroring by default" and list exact exceptions:
      provider API calls for sync/send and future approved integrations.
- [x] State what logs may contain: account id or hash, provider, operation,
      status, duration, error category, counts, and feature flags. State what
      logs must not contain.

### Task 2: Build Settings privacy surface

- [x] Add or update Settings Privacy tab to show connected providers, local data
      classes, provider API use, AI mode, cloud fallback state, and cache
      controls.
- [x] Show Gmail and Outlook permissions in human terms and link them to
      re-consent where supported.
- [x] Add controls for AI disabled/local/cloud fallback only if those modes are
      implemented. Otherwise show local-only current state.
- [x] Add SettingsFeature tests for copy keys, state rendering, toggles, and no
      unsupported controls.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/SettingsFeature && swift test`.

### Task 3: Add sanitized observability helpers

- [x] Add a small observability helper in `AppFoundation` or an existing core
      package for sanitized event fields and redaction.
- [x] Add categories for Sync, ProviderAuth, SendQueue, Search, Attachment,
      Privacy, and AI without logging raw content.
- [x] Add tests proving redaction removes email body-like, token-like, MIME
      body, prompt, and attachment fields from event metadata.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/AppFoundation && swift test`.

### Task 4: Replace unsafe or vague logs

- [x] Audit Swift files for direct `print`, `Logger`, and `os_log` use in sync,
      provider, compose, search, attachment, AI, and settings paths.
- [x] Replace unsafe logs with sanitized helpers. Keep useful status logs with
      counts and error categories.
- [x] Run the privacy grep validation and fix leaks.

### Task 5: Surface failure states without leaking content

- [ ] Ensure sync, send, search, and attachment failures show user-actionable
      categories: offline, missing credential, insufficient scope, rate limit,
      provider unavailable, unsupported operation, and unknown.
- [ ] Add feature tests for representative failure state copy in Settings,
      Compose, Thread, and Inbox where supported.
- [ ] Run relevant package tests listed in Validation Commands.

### Task 6: Add cache and account removal notes

- [ ] Document local cache deletion behavior for accounts, attachment bytes,
      indexes, drafts, and AI artifacts.
- [ ] Add or update tests proving account removal cascades local mail,
      attachments, indexes, drafts, and queue rows where those tables exist.
- [ ] Run all validation commands listed above and fix failures.

## Rollback / Recovery

If optional telemetry or privacy UI blocks release, disable export and keep
static local privacy copy. Do not weaken the no-raw-content logging rule.
