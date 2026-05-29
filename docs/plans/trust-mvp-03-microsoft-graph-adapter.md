# Plan: Trust MVP 03 - Microsoft Graph Adapter

## Summary

Add the first Microsoft Graph/Outlook provider adapter behind a feature flag,
using the provider contracts from tranche 01. This tranche should support
account records, OAuth contract scaffolding, folder listing, message fetch,
per-folder delta sync, attachment fetch, send, and basic mutations required by
Trust MVP. Keep shared mailbox, delegated mailbox, Exchange admin policies, and
enterprise governance out of scope.

## Impact Checklist

- Business flow: users can connect an Outlook/Microsoft 365 account and see
  reliable mailbox state without Gmail label assumptions.
- Domain boundaries: Graph DTOs and delta URLs stay in `MailProviders/Graph`;
  `MailSync` consumes provider-neutral operations and checkpoints.
- API / contracts: add Graph provider protocols and factories; shared UI/store
  APIs should remain provider-neutral.
- Schema / data model: persist Outlook accounts, folders/categories, messages,
  attachments, and per-folder delta checkpoints additively.
- Auth / permissions: use delegated Microsoft Graph scopes; keep least
  privilege and visible re-consent behavior.
- Cache / queue / async workflow: Graph delta is per-folder and uses opaque
  `@odata.nextLink` and `@odata.deltaLink` URLs; do not synthesize global Gmail
  style history ids.
- Observability: privacy-safe Graph sync/send/mutation logs; no raw body,
  token, attachment, or Graph URL with embedded tokens in logs.
- Migration: additive only; existing Gmail data remains untouched.
- Rollback: Graph feature flag disables account connection and sync while new
  schema remains dormant.
- Debt impact: retires single-provider architecture; may introduce known
  Outlook gaps documented as explicit non-goals.
- ADR required: update ADR 0005 if Graph behavior forces a contract change.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Auth/AuthKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/SettingsFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ! /usr/bin/grep -R -n -E '(Authorization:|Bearer |refresh_token|client_secret|Logger.*(body|html|payload|attachment|deltaLink)|print\\(.*(body|html|payload|attachment|deltaLink))' Apps Packages --include='*.swift' --exclude-dir=.build --exclude='*Tests.swift'`

### Task 1: Record Graph scope and source constraints

- [x] Update ADR 0005 or add `docs/trust-mvp-graph-notes.md` with Microsoft
      Graph constraints from official Microsoft docs.
- [x] State that message delta query is per-folder, uses opaque next/delta
      links, and must track each synced folder independently.
- [x] State least-privilege delegated scopes for Trust MVP: read/write mail as
      needed for sync and mutations, send mail for sending, offline access for
      refresh, and OpenID profile/email for account identity.
- [x] State non-goals: shared/delegated mailboxes, application permissions,
      tenant admin flows, calendar/contacts, and enterprise policy UI.

### Task 2: Add Graph DTOs and API client seam

- [ ] Create `Packages/Mail/MailProviders/Sources/MailProviders/Graph/`.
- [ ] Add Graph DTOs for mail folder, message, recipient/address, body,
      attachment metadata, delta response, error response, and send result.
- [ ] Add a `GraphAPI` protocol covering folder list, folder message delta,
      message get, attachment get, send mail or create/send draft, mark read,
      move/archive/trash, flag/unflag where supported, and category operations
      only if needed for canonical starred/flagged behavior.
- [ ] Add a `GraphAPIClient` with request construction, auth header injection,
      JSON decoding, status/error mapping, and no raw content logging.
- [ ] Add tests using `MockURLProtocol` or existing test helpers for successful
      decode, error mapping, rate limit, auth failure, and privacy-safe logs.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`.

### Task 3: Add Outlook auth scaffolding

- [ ] Inspect `AuthKit` and current Gmail OAuth flow before adding Microsoft
      types.
- [ ] Add Microsoft OAuth config and token storage types without weakening
      existing Gmail token handling.
- [ ] Ensure account records store provider as Outlook/Graph and keep display
      identity separate from provider credentials.
- [ ] Add tests for config validation, token store isolation by provider/account,
      missing credential errors, and re-consent signals.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Auth/AuthKit && swift test`.

### Task 4: Implement Graph mapping to canonical mail records

- [ ] Add `GraphMapper` that maps Graph folders, messages, body content,
      recipients, read state, sent state, attachments, flagged state, categories,
      and deleted/moved items into canonical records.
- [ ] Preserve provider-specific external ids in existing ids or mapping records
      without colliding with Gmail ids across accounts.
- [ ] Add tests for HTML body, text body, attachments, unread, sent,
      flagged/starred mapping, trash/deleted items, and category preservation.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`.

### Task 5: Add Graph sync engine support behind a flag

- [ ] Extend `MailSync` with a provider-neutral sync runner or a Graph-specific
      engine that still emits existing `SyncEvent` semantics.
- [ ] Persist Graph folder checkpoints as opaque delta URLs per account/folder;
      never parse token contents.
- [ ] Implement initial sync over selected folders and incremental delta using
      nextLink until deltaLink completes.
- [ ] Add tests for initial sync, multi-page nextLink, final deltaLink,
      deletion/tombstone, rate limit pause, auth failure, and folder checkpoint
      isolation.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`.

### Task 6: Wire Outlook account UI as disabled-by-default or feature-gated

- [ ] Add provider selection UI in Settings or onboarding only if the Graph auth
      and sync seams are complete enough for a test account. Otherwise show an
      internal feature flag path only.
- [ ] Make user-facing copy honest: Outlook support is beta until real account
      smoke tests pass.
- [ ] Add SettingsFeature tests for provider list, disabled state, and no Gmail
      regression.
- [ ] Run all validation commands listed above and fix failures.

## Rollback / Recovery

If Graph blocks release, disable the Graph feature flag and leave schema and
provider code dormant. Do not remove Gmail hardening or provider contracts.
