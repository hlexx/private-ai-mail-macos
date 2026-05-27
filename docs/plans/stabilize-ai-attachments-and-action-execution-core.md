# Plan: Stabilize AI Attachments and Build Action Execution Core

## Summary

Implement the next architecture slice for `private-ai-mail-macos`: first complete the current Gmail sync, AI prompt-budget, and attachment-evidence stabilization work; then add the supervised action-execution foundation needed for real Snooze, Send to, CRM, Slack, and Notion workflows. This plan intentionally stops before wiring Team Connect providers or making external SaaS calls. The goal is to create a durable action contract, approval model, and local outbox/audit persistence that future UI and integration work can use without bypassing privacy boundaries.

## Impact Checklist

- Business flow: makes thread briefs, draft replies, and attachment summaries safer to trust before turning AI output into user-visible actions; prepares real execution for currently decorative workflow actions.
- Domain boundaries: `AIPrompts`, `AttachmentRAG`, `MailSync`, and `Persistence` keep their existing ownership for the stabilization phase; `IntegrationDomain` becomes the owner of supervised workflow action contracts; `Persistence` owns action outbox records and migrations.
- API / contracts: add typed action contracts in `IntegrationDomain`; do not remove existing `AIService`, `MailMutator`, `ComposeService`, or feature APIs.
- Schema / data model: complete the attachment schema correction from the existing stabilization plan; then add additive action outbox, attempt, and audit tables.
- Auth / permissions: no new Gmail, Slack, Notion, HubSpot, Salesforce, or cloud broker scopes in this plan.
- Cache / queue / async workflow: preserve AI artifact cache identities; introduce local action outbox state but do not start background external delivery yet.
- Observability: add privacy-safe logs for stabilization failures and action state transitions; never log raw email bodies, attachment bytes, extracted text, prompt bodies, model output, bearer tokens, refresh tokens, or connector secrets.
- Migration: additive or data-preserving GRDB migrations only; any table rebuild must copy existing rows and preserve indexes and foreign keys.
- Rollback: stabilization tasks should be separately revertible except shipped DB migrations; action-core tables can remain dormant if later action wiring is disabled.
- Debt impact: retires prompt-budget drift, attachment-evidence hallucination risk, artifact lifecycle coupling, and empty integration namespaces; introduces no external integration debt.
- ADR required: yes, because this changes background sync invariants, schema/cache contracts, shared action contracts, approval semantics, and local queue/audit architecture.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && swiftlint --strict --reporter xcode`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIPrompts && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIRuntime && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Attachments/AttachmentRAG && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Integrations/IntegrationDomain && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Integrations/IntegrationBroker && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Integrations/IntegrationConnectors && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ! rg -n '(Bearer |refresh_token|client_secret|Logger.*(body|html|payload|attachment)|print\\(.*(body|html|payload|attachment))' Apps Packages --glob '*.swift' --glob '!**/Tests/**' --glob '!**/.build/**'`

### Task 1: Complete the AI, sync, and attachment stabilization baseline

- [x] Open `docs/plans/fix-review-findings-sync-ai-attachments.md` and treat it as the required baseline before action-core implementation.
- [x] Create or update the stabilization ADR described there, covering Gmail history pagination, attachment artifact lifecycle, prompt input budget semantics, attachment evidence grounding, and privacy-safe logging.
- [x] Fix Gmail history pagination in `Packages/Mail/MailSync/Sources/MailSync/IncrementalSync.swift`: every page in one history run must use the original persisted `startHistoryId`, and `sync_state.history_id` must advance only after all pages complete.
- [x] Preserve unchanged attachment blobs, extractions, chunks, and AI artifacts during normal thread/message refresh; only real message or attachment deletion may cascade-delete those records.
- [x] Enforce total rendered-input budgets for `ThreadBriefTask` and `DraftReplyTask`, not per-message budgets.
- [x] Validate `attachmentSummary` evidence in `AttachmentRAG` against existing chunks before persisting successful artifacts.
- [x] Align `attachment_extraction`, `attachment_chunk`, and `attachment_ai_artifact` `extraction_version` schema contracts with the runtime type and add data-preserving migration coverage.
- [x] Fix misleading idle attachment UI copy and any current `ThreadFeature` warnings without enabling attachment Preview.
- [x] Run every validation command listed in `docs/plans/fix-review-findings-sync-ai-attachments.md` and fix failures before starting Task 2.

### Task 2: Record ADR 0004 for supervised action execution

- [x] Create `docs/adr/0004-supervised-action-execution-core.md`.
- [x] State the sequence: stabilization first, action core second, UI wiring third, Team Connect providers last.
- [x] Define the trust boundary: raw email bodies, attachments, extracted text, local indexes, prompts, model output, and generated drafts stay on device unless a user explicitly sends or approves a minimized payload.
- [x] Define the action pipeline: `ActionCommand -> Policy/Approval -> Local Outbox -> Executor -> Result/Audit`.
- [x] Define action identity: `op_id`, `account_id`, target ids, action kind, schema version, idempotency key, approval state, status, attempt count, created/updated timestamps, and optional external result id.
- [x] Define approval levels for local low-risk actions, send-mail actions, external writes, destructive actions, and sensitive legal/finance/HR actions.
- [x] Define out-of-scope work for this plan: no Slack/Notion/CRM provider calls, no cloud broker delivery, no new OAuth scopes, no automatic external writes, no action-router model task.
- [x] Document rollback: leave additive action tables dormant and disable UI entry points if action execution blocks release.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check` and fix formatting issues.

### Task 3: Add the supervised action domain model

- [x] Replace the `IntegrationDomain` namespace-only stub with a typed action domain surface while preserving `IntegrationDomain.moduleName` for compatibility.
- [x] Add action kind/types for at least: `draftReply`, `sendReply`, `archiveThread`, `starThread`, `markRead`, `trashThread`, `snoozeThread`, `sendToSlack`, `createNotionPage`, and `logToCRM`.
- [x] Add `ActionTarget` cases for thread, message, attachment, and integration destination targets without importing UI or provider modules.
- [x] Add `ActionPayload` or equivalent typed/enveloped payload model with a schema version and JSON-encodable body; keep provider-specific payload details out of UI modules.
- [x] Add `ApprovalRequirement`, `ApprovalState`, `ActionStatus`, `ActionFailureKind`, `ActionResult`, and `ActionAuditEvent` types.
- [x] Add idempotency helpers so the same user action can produce a stable local idempotency key without embedding raw body text in the key.
- [x] Add policy helpers that classify default approval requirements: local label mutations can be low-risk, sending email requires explicit user approval, external writes require preview and confirm, destructive or sensitive actions require explicit confirm.
- [x] Add `IntegrationDomain` tests proving all action kinds have stable raw values, approval defaults, status transitions, codable round trips, and privacy-safe idempotency keys.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Integrations/IntegrationDomain && swift test` and fix failures.

### Task 4: Add local action outbox persistence

- [ ] Inspect current GRDB migration numbering in `Packages/Core/Persistence/Sources/Persistence/Migrator.swift` and add the next migration without reusing an existing migration name.
- [ ] Add `action_outbox` with fields for `op_id`, `account_id`, target kind/id fields, action kind, action schema version, idempotency key, approval state, status, payload JSON, result JSON, last error kind/code, attempt count, created at, updated at, approved at, and completed at.
- [ ] Add `action_attempt` with one row per execution attempt, linked to `action_outbox`, storing attempt number, status, started/completed timestamps, retryable flag, and privacy-safe error code/message.
- [ ] Add `action_audit_event` with one row per lifecycle event, linked to `action_outbox`, storing event kind, actor kind, timestamp, and privacy-safe metadata JSON.
- [ ] Add indexes for account/status, idempotency key, target lookup, and updated-at ordering.
- [ ] Add record types under `Packages/Core/Persistence/Sources/Persistence/Records` for the new tables.
- [ ] Ensure payload/result/error JSON fields may store local sensitive content on device, but no logs or test fixtures include private mailbox content.
- [ ] Add `Persistence` tests for fresh migration, duplicate idempotency handling, status transition persistence, attempt ordering, audit insertion, and cascade behavior on account deletion.
- [ ] Do not wire `ActionSheetView`, `ThreadView`, `MailMutator`, or external integrations to the outbox in this task unless required to keep the build compiling.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test` and fix failures.

### Task 5: Run final architecture-gate validation

- [ ] Run every command in `## Validation Commands`.
- [ ] Confirm `git status --short --branch` shows only intended doc, domain, persistence, and stabilization changes.
- [ ] Inspect changed logs for privacy issues: no raw email bodies, raw attachment text/bytes, prompt bodies, model output, bearer tokens, refresh tokens, or connector secrets.
- [ ] Summarize what is now ready for the next plan: UI wiring to action outbox, local mail action executors, Snooze implementation, and Team Connect broker/provider adapters.
- [ ] Explicitly list deferred work in completion notes: Slack/Notion/CRM calls, cloud broker delivery, action-router model task, external connector auth, automatic rules, attachment Preview, DOCX/OCR extraction, and notarized release packaging.

## Rollback / Recovery

- If Task 1 destabilizes sync or AI, roll back the failing subsystem task from `docs/plans/fix-review-findings-sync-ai-attachments.md` and do not start action-core work.
- If ADR 0004 needs revision, stop after Task 2 and update the ADR before adding domain or persistence code.
- If `IntegrationDomain` action types create dependency or naming conflicts, keep the domain package changes and avoid importing them into feature/UI packages until a separate UI-wiring plan.
- If action outbox migrations ship, do not drop tables in rollback. Leave them dormant and disable any callers.
- If persistence tests fail because an existing user database has a partially migrated attachment schema, add data-preserving compatibility logic instead of deleting or recreating user data.

## Notes

- Execute from `/Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos`, not the parent `Re_Box` folder.
- Keep this plan focused on architecture steps 1-4 only: stabilization, ADR, action domain, and action outbox persistence.
- Do not implement Team Connect provider calls in this plan. Team Connect should start only after the action outbox and approval contracts are stable.
- Do not make hidden fallbacks. Unsupported or unwired actions must be visibly disabled, dormant, or explicitly deferred.
