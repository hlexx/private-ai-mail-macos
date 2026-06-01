# Plan: Execute Trust MVP Action Layer

## Summary
Build the next Trust MVP increment after `7cdeb8a`: turn the integrated action-core domain and `action_outbox` persistence into a safe local/Gmail action execution layer with approval UI, then run an Outlook readiness spike. Use native ralphex Codex mode from the repo root. Intended command: `ralphex --codex --pass-claude-md --branch trust-mvp-action-layer --task-model gpt-5.5:high --review-model gpt-5.5:high docs/plans/execute-trust-mvp-action-layer.md`.

## Impact Checklist
- Business flow: users can trigger controlled mail actions instead of only reading/searching mail.
- Domain boundaries: keep action domain/provider/UI boundaries separate; no provider SDK leakage into UI.
- API / contracts: add internal executor contract for action execution; no external product API.
- Schema / data model: prefer existing `action_outbox`, `action_attempt`, and `action_audit_event`; add migration only if locking/retry fields are strictly required.
- Auth / permissions: use existing Gmail permissions; do not add Outlook scopes without ADR.
- Cache / queue / async workflow: action outbox becomes the local durable queue.
- Observability: add privacy-safe action lifecycle logs and persisted audit events.
- Migration: additive only if required; migration tests mandatory.
- Rollback: revert the branch merge; if needed, leave action tables dormant and hide UI entry points.
- Debt impact: retires dormant action-core debt; may introduce deferred Outlook mutation debt.
- ADR required: no for local/Gmail executor within ADR 0004; yes before new Outlook Graph scopes or mutation contracts.

## Validation Commands
- `git status --short --branch`
- `git diff --check`
- `swiftlint --strict --reporter xcode`
- `./scripts/verify-trust-mvp.sh`
- `cd Packages/Integrations/IntegrationDomain && arch -arm64 swift test`
- `cd Packages/Core/Persistence && arch -arm64 swift test`
- `cd Packages/Mail/MailProviders && arch -arm64 swift test`
- `cd Packages/Mail/MailSync && arch -arm64 swift test`
- `cd Packages/Features/InboxFeature && arch -arm64 swift test`
- `cd Packages/Features/ThreadFeature && arch -arm64 swift test`
- `tuist generate --no-open`
- `xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 1: Add local action executor boundary
- [x] Inspect `Packages/Integrations/IntegrationDomain`, `Packages/Core/Persistence`, `Packages/Mail/MailProviders`, `Packages/Mail/MailSync`, `Packages/Features/InboxFeature`, and `Packages/Features/ThreadFeature` for existing action/provider patterns.
- [x] Add an internal executor protocol/service that consumes `ActionCommand` or persisted `ActionOutboxRecord` and returns `ActionResult`.
- [x] Support local MVP action kinds: `draftReply`, `archiveThread`, `starThread`, `markRead`, and `trashThread`.
- [x] Keep executor code outside UI packages and keep provider-specific code outside `IntegrationDomain`.
- [x] Persist lifecycle transitions through `action_outbox`, `action_attempt`, and `action_audit_event`.
- [x] Ensure idempotency: repeating the same completed `op_id` must not execute the provider write again.
- [x] Add tests for valid transition flow, duplicate idempotency, failed action persistence, and privacy-safe audit metadata.
- [x] Run `cd Packages/Integrations/IntegrationDomain && arch -arm64 swift test`.
- [x] Run `cd Packages/Core/Persistence && arch -arm64 swift test`.

### Task 2: Wire Gmail actions through the provider layer
- [x] Locate the current Gmail mutation APIs or add the minimal provider-facing methods required for archive, star, mark read, trash, and draft creation.
- [x] Implement Gmail executor adapter behind the executor boundary from Task 1.
- [x] Map Gmail API success to completed outbox status with privacy-safe result metadata.
- [x] Map Gmail API failures to retryable/non-retryable `ActionFailureKind` without logging raw message bodies, attachment text, prompts, tokens, or provider secrets.
- [x] Preserve existing Gmail sync invariants and do not change Gmail history checkpointing behavior.
- [x] Add tests for successful Gmail mutation, duplicate execution suppression, expired auth, retryable provider failure, and non-retryable provider failure.
- [x] Run `cd Packages/Mail/MailProviders && arch -arm64 swift test`.
- [x] Run `cd Packages/Mail/MailSync && arch -arm64 swift test`.

### Task 3: Add minimal approval and outbox UI
- [x] Add user-triggered actions in Inbox/Thread UI for the MVP action kinds without introducing AI auto-actions.
- [x] Require explicit confirmation for destructive actions and draft/send-related actions; allow low-risk label mutations to use a fast confirm flow.
- [x] Add an outbox/action state surface for pending, running, completed, failed, and retryable failed actions.
- [x] Add retry affordance only for retryable failures and prevent retry for completed or non-retryable actions.
- [x] Use privacy-safe, user-actionable copy for provider/auth/network failures.
- [x] Do not wire Slack, Notion, CRM, Team Connect, cloud broker, or action-router model tasks.
- [x] Add UI/view-model tests for approval required, action queued, completed, failed retryable, failed non-retryable, and no auto-action on AI output.
- [x] Run `cd Packages/Features/InboxFeature && arch -arm64 swift test`.
- [x] Run `cd Packages/Features/ThreadFeature && arch -arm64 swift test`.

### Task 4: Run Outlook Trust MVP readiness spike
- [x] Inspect current Microsoft/Outlook provider, auth, sync, and settings code paths.
- [x] Document whether Outlook currently supports read/sync only, draft creation, message mutation, or no usable provider boundary.
- [x] Identify missing Microsoft Graph scopes, contracts, or sync invariants required before Outlook mutations can be enabled.
- [x] Do not add new Graph scopes, mutation behavior, or schema changes in this task unless an ADR is created first.
- [x] Create or update a short plan note under `docs/plans/` describing the next Outlook implementation step and whether ADR is required.
- [x] Add tests only for compatibility surfaces touched during inspection; otherwise keep this task documentation-only.
- [x] Run `git diff --check`.
- [x] Run the narrow package tests for any package touched by the spike.

### Task 5: Run full Trust MVP release gate
- [x] Run every command in `## Validation Commands` from the repository root.
- [x] Inspect changed logging for raw email bodies, raw attachment text or bytes, prompt bodies, model output, bearer tokens, refresh tokens, and connector secrets.
- [x] Confirm `git status --short --branch` shows only intended changes.
- [x] Confirm any migration added is additive, tested from fresh DB and upgraded DB paths, and has rollback notes.
- [x] Summarize completed behavior by subsystem: action executor, Gmail provider wiring, approval/outbox UI, Outlook spike, docs.
- [x] Explicitly list deferred work: Slack/Notion/CRM calls, cloud broker delivery, action-router model task, external connector auth, automatic rules, Snooze, Outlook mutations if not proven, DOCX/OCR extraction, attachment Preview, notarized release packaging.

Task 5 release gate evidence:
- Validation passed: `git status --short --branch`, `git diff --check`, `swiftlint --strict --reporter xcode`, `./scripts/verify-trust-mvp.sh`, all six explicit `arch -arm64 swift test` package commands listed above, `tuist generate --no-open`, and the MacApp Debug `xcodebuild build` command with signing disabled.
- Privacy logging inspection: changed action audit and result metadata stores action kind, target kind, status, executor/provider labels, result, retryability, provider error category, and external-result presence only. It does not persist or log raw email bodies, raw attachment text or bytes, prompt bodies, model output, bearer tokens, refresh tokens, or connector secrets.
- Migration confirmation: this action-layer plan did not add or modify migration files. Existing additive action outbox migration coverage still passed fresh and upgrade paths through Persistence tests, including `freshMigrationCreatesActionOutboxTablesAndIndexes`, `freshDatabaseMigrationCreatesTrustMVPReleaseGateSchema`, and `upgradeStyleMigrationPreservesSeededGmailDataAndAcceptsOutlookRows`. Rollback remains the documented disable-UI/executor path with additive tables left dormant.
- Completed behavior by subsystem: IntegrationDomain now exposes the local MVP executor boundary and supported action kinds; Persistence executes idempotent outbox lifecycle, attempts, and audit persistence; Gmail provider wiring supports draft, archive, star, mark-read, and trash through the executor adapter; Inbox and Thread UI require explicit approval where needed, show outbox state, and gate retries; the Outlook spike documents that mutations remain disabled until an ADR-backed provider/account/sync contract is implemented; docs now capture the release gate and Outlook readiness outcome.
- Deferred work: Slack/Notion/CRM calls, cloud broker delivery, action-router model task, external connector auth, automatic rules, Snooze, Outlook mutations, DOCX/OCR extraction, attachment Preview, and notarized release packaging.

## Rollback / Recovery
- Revert the final merge commit for this plan if action execution blocks release.
- If schema changes were added, keep rollback as "disable UI/executor and leave additive tables dormant"; destructive down-migration is not required for local app rollback.
- If Gmail mutation risk is high, disable Gmail executor entry points and keep draft-only/local actions.
- If Outlook scope or mutation questions remain unresolved, leave Outlook read/sync-only and require a separate ADR-backed plan.

## Notes
- Keep all future task checkboxes unchecked for ralphex resume compatibility.
- Execute from `/Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos`.
- Prefer native Codex executor: `ralphex --codex --pass-claude-md --branch trust-mvp-action-layer --task-model gpt-5.5:high --review-model gpt-5.5:high docs/plans/execute-trust-mvp-action-layer.md`.
- Do not pop or delete existing stashes unless the user explicitly asks.
