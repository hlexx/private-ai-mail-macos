# Plan: Trust MVP 08 - Regression Suite and Release Gate

## Summary

Turn the Trust MVP into a repeatable release gate. The product is not done until
Gmail and Outlook provider flows, search, send queue, attachments, privacy
logging, offline behavior, and app build checks pass from one command or a
documented manual checklist. This tranche creates the automated and manual gate;
it does not add new product capabilities.

## Impact Checklist

- Business flow: release quality is judged by daily mail workflows, not by app
  build success alone.
- Domain boundaries: tests stay close to package ownership; the gate script
  orchestrates existing tests without embedding product logic.
- API / contracts: no new runtime APIs expected; may add test support fixtures.
- Schema / data model: no schema changes expected.
- Auth / permissions: live account smoke tests must be clearly manual and must
  not commit credentials.
- Cache / queue / async workflow: regression tests cover sync, send queue,
  search indexing, and attachment cache failure paths.
- Observability: gate includes privacy grep and no raw-content log checks.
- Migration: migration tests must run as part of the gate.
- Rollback: if a gate step is too flaky, mark it manual with owner and expiry;
  do not silently remove it.
- Debt impact: retires undocumented release confidence and drift between docs
  and code.
- ADR required: no unless a new release policy changes distribution contracts.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ./scripts/verify-trust-mvp.sh`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && swiftlint --strict --reporter xcode`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && tuist generate --no-open`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 1: Define Trust MVP acceptance criteria

- [x] Create `docs/trust-mvp-release-gate.md`.
- [x] Define automated acceptance criteria for Gmail, Graph, search, send queue,
      attachment baseline, privacy/observability, migrations, and build.
- [x] Define manual smoke criteria for real Gmail and real Outlook accounts:
      connect, initial sync, refresh, search, send/reply, archive, read/unread,
      star/flag, trash, attachment download/preview, offline open, re-consent,
      and rate-limit/error visibility.
- [x] Define explicit non-goals for this release gate: iCloud/IMAP,
      shared/delegated mailboxes, team inbox, CRM writes, Slack/Notion writes,
      send later, auto-send, and mobile companion.

### Task 2: Add fixture coverage for provider contracts

- [x] Add or organize fixtures for Gmail labels/history/messages/attachments
      and Graph folders/delta/messages/attachments.
- [x] Ensure fixtures do not contain real tokens or user-private mail content.
- [x] Add tests that both providers map into canonical mailbox/search/send
      contracts consistently where their capabilities overlap.
- [x] Run provider and sync package tests.

### Task 3: Add Trust MVP verification script

- [ ] Create `scripts/verify-trust-mvp.sh` as a strict bash script with clear
      section output and non-zero failure on any required gate.
- [ ] Include `git diff --check`, SwiftLint, package tests for MailDomain,
      MailProviders, MailSync, MailIndex, Persistence, AuthKit, ComposeFeature,
      InboxFeature, ThreadFeature, SettingsFeature, AttachmentKit, and
      AttachmentRAG where those packages exist.
- [ ] Include privacy grep checks for tokens, raw bodies, raw prompts, raw
      attachment bytes, and unsafe logger/print patterns.
- [ ] Make expensive `xcodebuild build` optional behind an environment variable
      or separate final section if needed for local speed, but document the full
      release command.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ./scripts/verify-trust-mvp.sh`.

### Task 4: Add migration and rollback checks

- [ ] Ensure `PersistenceTests` cover fresh database migration and upgrade-style
      migration with seeded Gmail data plus Outlook-compatible rows.
- [ ] Add tests for account deletion cascade across messages, labels/folders,
      attachments, search index, drafts, send queue, and AI artifacts where
      those tables exist.
- [ ] Document rollback behavior for feature-gated Graph, search, send queue,
      attachment preview, and privacy telemetry.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`.

### Task 5: Add release note and docs consistency checks

- [ ] Update `README.md`, `NOTES.md`, or release notes to state current Trust
      MVP support honestly: Gmail stable, Outlook beta or stable depending on
      implementation, no iCloud/IMAP unless implemented, optional local AI.
- [ ] Add a docs consistency checklist so claims about M365, FTS, DOCX/OCR,
      Spotlight, send queue, or privacy match code and tests.
- [ ] Do not edit sibling `../EMAIL_ALF` in this app plan unless explicitly
      required by the user in a separate docs repo pass.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`.

### Task 6: Run the full gate and capture evidence

- [ ] Run all validation commands listed above.
- [ ] Capture command outcomes in `docs/trust-mvp-release-gate.md` with date,
      commit SHA, and any manual steps that remain.
- [ ] If any gate is blocked, document the exact blocker, owner, and required
      fix instead of weakening the gate.

## Rollback / Recovery

If the verification script is too broad for local machines, split slow commands
into an explicit `FULL_TRUST_MVP_GATE=1` mode. Do not remove privacy grep,
migration tests, or provider contract tests from the default gate.
