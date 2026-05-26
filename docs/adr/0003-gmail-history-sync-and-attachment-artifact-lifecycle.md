# ADR 0003: Gmail History Sync and Attachment Artifact Lifecycle

Date: 2026-05-26

Status: Accepted

## Context

Gmail incremental sync, local thread persistence, and attachment intelligence
share a release-critical boundary: remote mailbox changes must update local
thread state without invalidating unrelated on-device AI artifacts. The same
flow also renders thread context into model prompts and records attachment
summary evidence that users may rely on.

Before this ADR, several contracts were implicit:

- a paginated Gmail history run could mix the persisted checkpoint with newer
  page response ids;
- normal thread refresh could delete and recreate unchanged attachment metadata,
  cascading into attachment blobs, extractions, chunks, and AI artifacts;
- prompt task input limits could be interpreted as a per-message body limit
  rather than a total rendered-input budget;
- attachment summary evidence could be accepted without proving that each quote
  is grounded in the extracted chunk text.

These behaviors affect mailbox correctness, local cache durability, AI output
trustworthiness, and privacy boundaries.

## Decision

- Gmail history pagination uses the original persisted `startHistoryId` for
  every `users.history.list` page in one incremental run. The local
  `sync_state.history_id` is advanced only after all pages are consumed, using
  the final returned history id as the next checkpoint.
- Normal thread or message refresh preserves unchanged attachment blobs,
  extractions, chunks, and AI artifacts. Cascade delete is reserved for real
  attachment, message, or account deletion, not for label-only or
  content-identical refreshes.
- `PromptTaskMetadata.maxInputCharacters` is the total rendered-input budget
  for a model task. It is not a per-message limit. Thread brief and draft reply
  prompts must spend one task-level budget across the rendered thread context.
- Attachment summary evidence is valid only when every evidence chunk index
  points to an existing chunk and each quoted evidence string is present in
  that chunk after conservative whitespace normalization.
- Privacy-safe observability is required. Logs may include identifiers and
  failure categories needed for operation, but must not include raw email
  bodies, attachment bytes, extracted text, prompt bodies, or model output.

## Consequences

- Multi-page Gmail history sync has a stable checkpoint contract and cannot skip
  changes by advancing the request id before the pagination run completes.
- Attachment AI caches survive ordinary mailbox refreshes and are invalidated by
  explicit cache identity changes or real deletion, not by persistence churn.
- Prompt budget tests can reason about the full rendered model input instead of
  multiplying a nominal task budget by message count.
- Ungrounded attachment summary evidence is rejected before persistence, keeping
  successful artifact rows limited to summaries that can be traced back to local
  chunks.
- Logs remain useful for diagnosing sync and evidence validation failures
  without exposing private message or attachment contents.

## Rollback

If the Gmail pagination contract regresses sync, revert the incremental sync
change while keeping the documented invariant for the next repair attempt. If
attachment artifact preservation regresses thread persistence, temporarily
disable attachment summary UI entry points and leave attachment data-plane
tables dormant rather than dropping local artifact tables. If evidence
validation is too strict for real model output, fail invalid summaries with a
retryable error and tune validation; do not persist ungrounded evidence.
