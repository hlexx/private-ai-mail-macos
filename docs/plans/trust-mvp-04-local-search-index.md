# Plan: Trust MVP 04 - Local Search Index

## Summary

Replace the `MailIndex` stub with the Trust MVP search layer. Search must work
locally across Gmail and Outlook cached mail, with explicit server fallback for
provider-specific queries that the local index cannot satisfy. The MVP target is
full-text search over subject, sender, recipients, snippets, body text, and
attachment metadata, plus structured filters for account, mailbox, from, to,
date, unread, sent, and has attachment. Semantic search is not required for this
Trust MVP tranche.

## Impact Checklist

- Business flow: users can find mail faster than relying on provider web UIs.
- Domain boundaries: `MailIndex` owns query parsing and index reads/writes;
  `Persistence` owns FTS schema; providers own optional server fallback.
- API / contracts: add stable `MailSearchQuery`, `MailSearchResult`, and
  indexing APIs consumed by stores, not direct SQL from UI.
- Schema / data model: add FTS tables/triggers or explicit index maintenance
  additively; existing message rows remain source of truth.
- Auth / permissions: no new scopes for local search; server fallback uses
  existing provider read scopes.
- Cache / queue / async workflow: index updates run after message persistence
  and must tolerate backfill/rebuild.
- Observability: privacy-safe metrics for query latency, result count, local vs
  fallback path; no query body in logs unless redacted.
- Migration: additive FTS migration; rollback can leave FTS tables dormant.
- Rollback: disable search UI entry or fallback to existing basic filtering.
- Debt impact: retires `MailIndex` stub and ad hoc search assumptions.
- ADR required: update ADR 0005 only if search stores raw data outside local DB.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailIndex && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/InboxFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ! /usr/bin/grep -R -n -E '(Logger.*(body|html|query|payload|attachment)|print\\(.*(body|html|query|payload|attachment))' Apps Packages --include='*.swift' --exclude-dir=.build --exclude='*Tests.swift'`

### Task 1: Define search contracts

- [ ] Replace the `MailIndex` namespace-only stub with typed contracts:
      `MailSearchQuery`, `MailSearchFilter`, `MailSearchSort`,
      `MailSearchResult`, `MailSearchSnippet`, `MailIndexing`, and
      `MailSearching`.
- [ ] Support filters for account ids, provider, canonical mailbox, from, to,
      date range, unread, sent, has attachment, and attachment filename/mime.
- [ ] Support query modes for local full-text and provider fallback request.
- [ ] Add tests for query construction, default sorting, filter validation, and
      privacy-safe redaction of query descriptions.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailIndex && swift test`.

### Task 2: Add FTS persistence

- [ ] Add an additive migration for local search tables, using SQLite FTS5 if
      available in the target runtime.
- [ ] Index message subject, from, to, cc, snippet, body text, normalized body
      extracted from HTML where available, attachment filenames, and canonical
      mailbox fields needed for filtering.
- [ ] Do not index attachment bytes or extracted attachment full text in this
      tranche unless existing attachment extraction contracts already provide a
      safe chunk table and tests.
- [ ] Add rebuild metadata so the index can be rebuilt if the schema or
      tokenizer changes.
- [ ] Add `PersistenceTests` proving migration, insert/update/delete, cascade
      delete on account removal, and rebuild idempotency.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`.

### Task 3: Maintain the index during sync

- [ ] Wire index updates after Gmail and Graph message persistence without
      making providers depend on UI.
- [ ] Ensure bootstrap, incremental upsert, label/folder changes, sent-message
      insertion, and deletion update the index.
- [ ] Add tests that indexing survives repeated sync and does not duplicate
      rows.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`.

### Task 4: Implement local search execution

- [ ] Implement a `MailSearchService` in `MailIndex` that queries FTS and joins
      to canonical thread/message/account data.
- [ ] Return stable thread-level results with message hits, snippets, dates,
      account ids, mailbox hints, and attachment indicators.
- [ ] Add ranking that favors subject/from matches, recent messages, and exact
      phrase matches where reasonable.
- [ ] Add tests for body search, subject search, sender search, recipient
      search, date filter, account filter, mailbox filter, unread filter, has
      attachment filter, deletion, and empty query behavior.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailIndex && swift test`.

### Task 5: Add provider fallback seam

- [ ] Add a provider fallback protocol that can ask Gmail or Graph for server
      search when local search is incomplete or explicitly requested.
- [ ] Keep fallback results marked as remote and do not merge them silently into
      local DB without normal sync/fetch.
- [ ] Add tests proving fallback is not used for normal local queries and that
      fallback errors are user-visible but do not break local results.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailIndex && swift test`.

### Task 6: Wire search into InboxFeature

- [ ] Replace any search field placeholder behavior with `MailSearchService`
      results or an honest disabled state if service injection is unavailable.
- [ ] Ensure search can be cleared and normal inbox filters return.
- [ ] Add feature tests for search state, loading, empty results, local results,
      fallback failure, and filter interaction.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/InboxFeature && swift test`.
- [ ] Run all validation commands listed above and fix failures.

## Rollback / Recovery

If FTS migration or query performance blocks release, disable the search UI and
leave FTS tables dormant. Do not remove indexed data with destructive migration.

