# Plan: Fix Review Findings for Gmail Sync, AI Context and Attachment Evidence

## Summary

Fix the current full-review findings in `private-ai-mail-macos` without changing the product scope. The goal is to make Gmail incremental sync reliable across paginated history, preserve attachment AI artifacts across normal thread refreshes, enforce real per-task prompt context limits, validate attachment-summary evidence against extracted chunks, align attachment schema contracts, and clean the misleading attachment UI status. Do not implement attachment Preview, Snooze, Send to, DOCX/OCR extraction, cloud AI fallback, or new Gmail OAuth scopes in this plan.

## Impact Checklist

- Business flow: prevents missed Gmail updates, protects generated attachment summaries from unnecessary cache loss, and reduces `brief/draft failed` failures on long threads.
- Domain boundaries: `MailSync` owns Gmail sync cursor and thread persistence; `Persistence` owns migration/schema contracts; `AIPrompts` owns prompt budgets and parsers; `AttachmentRAG` owns chunk-grounded attachment summary validation; `ThreadFeature` owns UI state labels.
- API / contracts: no public app API should be removed; add internal helper contracts for thread reconciliation and attachment evidence validation; preserve existing `AIService.threadBrief`, `AIService.draftReply`, and `AIService.attachmentSummary`.
- Schema / data model: add a migration if needed to correct attachment `extraction_version` affinity to text while preserving existing rows and indexes; do not drop user data.
- Auth / permissions: no new Gmail scope; continue using existing read access for `users.messages.attachments.get`.
- Cache / queue / async workflow: attachment cache identity remains task id, prompt version, schema version, model id, extraction version, and input fingerprint; thread upsert must not cascade-delete unchanged attachment artifacts.
- Observability: add privacy-safe logs for multi-page history sync and attachment evidence validation failures; never log raw email bodies, extracted text, attachment bytes, prompt bodies, or model output.
- Migration: only additive or data-preserving migrations; any table rebuild must copy existing rows and re-create indexes/foreign keys.
- Rollback: each task should be revertible independently except schema migration, which must leave dormant compatible tables if rolled back.
- Debt impact: retires cache-lifecycle coupling, prompt-budget mismatch, evidence hallucination gap, and misleading UI state; introduces no temporary workaround.
- ADR required: yes, because the work changes background sync invariants, attachment artifact lifecycle, and schema/cache contracts. Create a focused ADR or update an existing one before implementation.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && swiftlint --strict --reporter xcode`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIPrompts && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIRuntime && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Attachments/AttachmentRAG && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ! rg -n '(Bearer |refresh_token|client_secret|Logger.*(body|html|payload|attachment)|print\\(.*(body|html|payload|attachment))' Apps Packages --glob '*.swift' --glob '!**/Tests/**' --glob '!**/.build/**'`

### Task 1: Record the sync and artifact lifecycle ADR

- [x] Create `docs/adr/0003-gmail-history-sync-and-attachment-artifact-lifecycle.md`.
- [x] State the Gmail history invariant: use the original `startHistoryId` for every page in a paginated `users.history.list` run, advance local `sync_state.history_id` only after all pages are consumed, and use the final returned history id as the checkpoint.
- [x] State the attachment artifact lifecycle invariant: normal thread/message refresh must preserve unchanged attachment blobs, extractions, chunks, and AI artifacts; cascade delete is only for real attachment/message/account deletion.
- [x] State the prompt budget invariant: `PromptTaskMetadata.maxInputCharacters` is a total rendered-input budget for the model task, not a per-message limit.
- [x] State the evidence invariant: attachment-summary evidence must point to an existing chunk and the quoted text must be found in that chunk.
- [x] Include privacy constraints: no raw bodies, attachment bytes, extracted text, prompt bodies, or model output in logs.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check` and fix formatting issues.

### Task 2: Fix Gmail history pagination checkpointing

- [x] Update `Packages/Mail/MailSync/Sources/MailSync/IncrementalSync.swift` so `api.listHistory(startHistoryId:pageToken:)` always receives the original persisted `historyId` during one paginated run.
- [x] Track the newest returned `response.historyId` separately and update `SyncStateRecord.historyId` only after the `nextPageToken` loop is complete.
- [x] Preserve existing behavior for single-page history responses, deleted threads, label changes, and `historyExpired`.
- [x] Extend `Packages/Mail/MailSync/Tests/MailSyncTests/MockGmailAPI.swift` to record `listHistory` call arguments.
- [x] Add a multi-page history test in `Packages/Mail/MailSync/Tests/MailSyncTests/MailSyncEngineTests.swift`: page 1 returns `nextPageToken`, page 2 returns final history id, both pages affect threads, every call uses the original `startHistoryId`, and the local checkpoint advances only after both pages.
- [x] Add a regression test where page 1 returns a newer `historyId` but also has `nextPageToken`; the second request must not use that newer id as `startHistoryId`.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test` and fix failures.

### Task 3: Preserve attachment artifacts during thread upsert

- [x] Extract shared thread persistence logic in `Packages/Mail/MailSync/Sources/MailSync` so `Bootstrap` and `IncrementalSync` can use the same message/attachment reconciliation behavior where practical.
- [x] Replace `IncrementalSync.upsertThread` delete-all message handling with reconciliation: upsert incoming messages, delete only local messages missing from the fetched thread, upsert incoming attachments, and delete only local attachments missing from the fetched message.
- [x] Ensure unchanged attachment rows keep the same `(account_id, message_id, id)` identity so `attachment_blob`, `attachment_extraction`, `attachment_chunk`, and `attachment_ai_artifact` are not cascade-deleted during label-only or content-identical refreshes.
- [x] Keep real deletion behavior: if Gmail no longer returns a message or attachment, related attachment rows and artifacts may still cascade-delete.
- [x] Add `MailSync` tests that seed an attachment blob/extraction/chunk/artifact, run an incremental label-only refresh of the same thread, and verify all artifact rows survive.
- [x] Add `MailSync` tests that remove an attachment from the fetched message and verify only that attachment's blob/extraction/chunk/artifact rows are deleted.
- [x] If `Bootstrap` is updated to use the shared helper, add or update bootstrap idempotency tests to prove no duplicate messages/attachments are created.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailSync && swift test`.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`.

### Task 4: Enforce total prompt input budgets for thread brief and draft reply

- [x] Extend `PromptTextBudget` in `Packages/AI/AIPrompts/Sources/AIPrompts/PromptTask.swift` with a total-budget renderer helper that consumes one task-level character budget across multiple sections/messages.
- [x] Update `ThreadBriefTask.renderUserPrompt` to treat `ThreadBriefTask.metadata.maxInputCharacters` as a total thread body budget, not a per-message budget.
- [x] Update `DraftReplyTask.renderUserPrompt` to treat `DraftReplyTask.metadata.maxInputCharacters` as a total thread body budget, not a per-message budget.
- [x] Preserve deterministic truncation markers so users and tests can tell that content was trimmed.
- [x] Keep attachment metadata in brief prompts, but ensure message bodies cannot exceed the task budget even when a thread has many messages.
- [x] Add `AIPrompts` tests with multiple long messages proving the full rendered prompt does not grow by `messageCount * maxInputCharacters`.
- [x] Add tests proving small threads render unchanged and existing parser behavior remains unchanged.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIPrompts && swift test`.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIRuntime && swift test`.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIKit && swift test`.

### Task 5: Validate attachment summary evidence against chunks

- [x] Add an internal validator in `Packages/Attachments/AttachmentRAG/Sources/AttachmentRAG/AttachmentRAG.swift` that checks every `AIAttachmentEvidence.chunkIndex` exists and every evidence quote appears in that chunk's text after conservative whitespace normalization.
- [x] Reject or fail the summary generation when evidence is not grounded; do not persist invalid `attachment_ai_artifact` rows.
- [x] Add privacy-safe OSLog for validation failure with attachment id, task id, prompt version, and failure kind only.
- [x] Keep `AttachmentSummaryParser` responsible for JSON/schema shape and keep chunk-grounding validation in `AttachmentRAG`, where chunk text is available.
- [x] Add `AttachmentRAG` tests for valid grounded evidence, missing chunk index, quote not present in chunk, malformed model output, and cache behavior after a validation failure.
- [x] Confirm invalid summary attempts do not create successful summary artifacts and do not poison cache.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Attachments/AttachmentRAG && swift test`.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/AI/AIPrompts && swift test`.

### Task 6: Align attachment schema contracts for extraction version

- [x] Change new-schema definitions in `Packages/Core/Persistence/Sources/Persistence/AttachmentDataPlaneMigrations.swift` so `extraction_version` is text in `attachment_extraction`, `attachment_chunk`, and `attachment_ai_artifact`.
- [x] Add a data-preserving migration, for example `M014`, for databases that already applied the integer-affinity tables: rebuild affected tables with text `extraction_version`, copy existing rows, preserve primary keys, foreign keys, indexes, and payload columns.
- [x] Keep compatibility with older partially migrated databases that may have `text`, `unsupported_reason`, `content_json`, `task_id`, `prompt_version`, `schema_version`, `input_fingerprint`, or other compatibility columns.
- [x] Add `Persistence` tests for a fresh database and for a simulated old database with integer-affinity `extraction_version`.
- [x] Verify existing attachment summaries still decode through `AttachmentRAG.fetchCachedSummary`.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Attachments/AttachmentRAG && swift test`.

### Task 7: Fix attachment summary idle UI text and ThreadFeature warnings

- [x] Update `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift` so idle attachment state does not say `local summary ready`; use neutral copy such as `ready to summarize` or no summary status until the user starts summarization.
- [x] Add or update `ThreadFeature` tests/snapshots for idle, summarizing, cached summary, unsupported, and failed attachment states.
- [x] Fix the current `ThreadFeature` test warnings by marking affected HTMLWebView tests `@MainActor` or by moving pure helpers out of main-actor isolation if that better matches the design.
- [x] Keep attachment Preview unchanged unless it is already real; this task must not turn the accepted Preview no-op into new behavior.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`.

### Task 8: Run release-gate validation and produce completion notes

- [x] Run every command in `## Validation Commands`.
- [x] Inspect logs/test output for remaining Swift concurrency warnings, privacy-sensitive logs, or unexpected network access in local AI tests.
- [x] Confirm `git status --short --branch` shows only intended changes.
- [x] Summarize changed files by subsystem: `MailSync`, `Persistence`, `AIPrompts`, `AttachmentRAG`, `ThreadFeature`, docs.
- [x] Include explicit notes for any intentionally deferred work: Preview, Snooze, Send to, DOCX/OCR, cloud AI fallback, and notarized release packaging.

Completion notes:

- Validation was run against the current Ralphex worktree. `tuist generate` was required first because the generated workspace and ignored `Frameworks/Sparkle.xcframework` dependency were not present in the worktree.
- Passing checks: `git diff --check`; all listed package tests for `MailSync`, `Persistence`, `AIPrompts`, `AIRuntime`, `AIKit`, `AttachmentRAG`, `ThreadFeature`, and `MailProviders`; final `xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`; and the privacy grep. OAuth protocol field names are constructed through typed constants so the gate still catches leaked token values and unsafe logging.
- SwiftLint source validation is clean with `swiftlint --strict --reporter xcode --disable-sourcekit` and reports 0 violations. The exact `swiftlint --strict --reporter xcode` command fails before linting in this local Xcode 26.2 toolchain with `SourceKittenFramework/library_wrapper.swift:58: Fatal error: Loading sourcekitdInProc.framework/Versions/A/sourcekitdInProc failed`; this is a local SourceKit runtime failure, not a source violation.
- Final build log has no Swift concurrency warnings. The only remaining build warning is AppIntents metadata extraction being skipped because `MacApp` has no AppIntents dependency.
- Local AI tests did not perform unexpected network access: `AIRuntime` skipped real MLX tests because `RB_RUN_REAL_MLX_TESTS` is unset or the model is missing, and the network-isolation test passed with zero network requests.
- Changed files by subsystem: `MailSync` updated incremental sync, bootstrap/thread reconciliation, mocks, and sync tests; `Persistence` updated attachment data-plane migrations and migration tests; `AIPrompts` updated total-budget rendering and prompt tests; `AttachmentRAG` added grounded-evidence validation and split helper files; `ThreadFeature` updated attachment status copy and tests; docs added ADR 0003 and this plan. Release-gate cleanup also touched `AuthKit` OAuth protocol-key handling and `MacApp` actor-isolation warnings.
- Deferred by design: attachment Preview, Snooze, Send to, DOCX/OCR extraction, cloud AI fallback, and notarized release packaging remain out of scope for this plan.

## Rollback / Recovery

- If the Gmail pagination fix regresses sync, revert Task 2 only; local schema/data should not be affected.
- If thread reconciliation regresses message storage, revert Task 3 and keep Task 2; attachment artifacts may again be over-deleted but Gmail checkpointing remains correct.
- If the extraction-version migration ships, do not drop attachment tables in rollback. Disable attachment-summary UI or `AttachmentRAG` usage and leave migrated tables dormant.
- If evidence validation is too strict for real model output, gate invalid summaries as failed with retry and keep raw extraction/chunks; do not persist ungrounded evidence.
- If prompt-budget changes reduce model quality, keep the total budget invariant and tune allocation strategy rather than returning to per-message caps.

## Notes

- Start from `/Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos`, not the parent `Re_Box` folder.
- Current known affected files include `Packages/Mail/MailSync/Sources/MailSync/IncrementalSync.swift`, `Packages/Mail/MailSync/Sources/MailSync/Bootstrap.swift`, `Packages/Core/Persistence/Sources/Persistence/AttachmentDataPlaneMigrations.swift`, `Packages/AI/AIPrompts/Sources/AIPrompts/PromptTask.swift`, `Packages/AI/AIPrompts/Sources/AIPrompts/ThreadBriefPrompt.swift`, `Packages/AI/AIPrompts/Sources/AIPrompts/DraftReplyPrompt.swift`, `Packages/Attachments/AttachmentRAG/Sources/AttachmentRAG/AttachmentRAG.swift`, and `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift`.
- Do not log or fixture private mailbox content. Synthetic tests must use generated non-private messages and attachment text.
