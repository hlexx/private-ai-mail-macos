# ADR 0003: Gmail History Sync and Attachment Artifact Lifecycle

Date: 2026-05-27

Status: Accepted

## Context

Gmail incremental sync, local attachment processing, and on-device AI summaries
share one user-facing trust path. A stale Gmail checkpoint can miss updates, and
over-eager thread refreshes can delete attachment blobs, extractions, chunks,
and AI artifacts even when Gmail only changed labels. Prompt-budget drift can
make long threads exceed the intended model input budget, while unvalidated
attachment evidence can make a persisted summary look grounded when the cited
text is not present in local chunks.

These behaviors must be stabilized before supervised action execution can rely
on thread briefs, draft replies, or attachment summaries.

## Decision

- In one paginated Gmail `users.history.list` run, every page request uses the
  original persisted `startHistoryId`.
- `sync_state.history_id` advances only after all history pages are consumed.
  The checkpoint is the newest final `historyId` returned by Gmail for that run.
- Normal thread or message refresh reconciles current Gmail state instead of
  delete-all replacement. Unchanged attachment rows keep their
  `(account_id, message_id, id)` identity.
- Attachment blobs, extractions, chunks, and AI artifacts survive label-only and
  content-identical refreshes. They cascade-delete only when the account,
  message, or attachment is actually removed.
- `PromptTaskMetadata.maxInputCharacters` is a total rendered-input budget for a
  model task. It is not a per-message budget.
- Attachment-summary evidence is accepted only when non-empty evidence is
  present for extracted chunks, every referenced `chunkIndex` exists, and each
  evidence quote is found in that chunk after conservative whitespace
  normalization.
- `extraction_version` is stored as text for attachment extractions, chunks, and
  AI artifacts, matching the runtime version contract.

## Trust Boundary

Raw email bodies, attachment bytes, extracted text, prompt bodies, model output,
bearer tokens, refresh tokens, and connector secrets must not be logged. Sync and
attachment validation logs may include privacy-safe identifiers and failure
kinds, such as account id, thread id, attachment id, task id, prompt version, and
schema version.

## Consequences

- Multi-page history sync has one stable cursor input and one commit point.
- Attachment AI cache identity is no longer coupled to routine message upsert
  implementation details.
- Long thread prompt rendering becomes bounded by task-level budgets.
- Persisted attachment summaries have local chunk-grounded evidence.
- The schema migration is data-preserving and compatible with older attachment
  tables that may have partial compatibility columns.

## Rollback

If incremental sync regresses, revert the history pagination change without
touching attachment schema. If reconciliation regresses message persistence,
revert only the shared upsert helper and accept the previous artifact churn until
a replacement fix ships. If the extraction-version migration ships, leave the
new tables dormant on rollback and disable attachment-summary entry points rather
than dropping user data.

## Out of Scope

This ADR does not add attachment Preview, Snooze, Send to, DOCX/OCR extraction,
cloud AI fallback, new Gmail OAuth scopes, Team Connect provider calls, or
external action execution.
