# ADR 0002: Prompt Task Registry and AI Artifact Versioning

Date: 2026-05-24

Status: Accepted

## Context

The app has multiple on-device AI tasks: thread briefs, draft replies, and
attachment summaries. Before this ADR, prompt text, context limits, schemas,
examples, parsers, retry behavior, and cache identity were owned by each task
independently. That made regressions hard to detect and made AI artifacts hard
to invalidate safely when prompts, schemas, model routing, or attachment
extraction changed.

Attachment intelligence also needs a stronger local data plane than provider
attachment metadata. Raw attachment bytes, extracted text, chunks, summaries,
and evidence references have different lifecycles and must remain on device.

## Decision

- Add a typed `PromptTask` registry in `AIPrompts`.
- Every model task has an explicit task id, prompt version, schema version,
  model profile, context budget, output token budget, examples, and privacy
  category.
- Run `threadBrief`, `draftReply`, and `attachmentSummary` through the same
  structured-output execution path in `AIRuntime`.
- Keep compatibility wrappers for existing brief and draft reply prompt entry
  points while routing their implementation through the registry.
- Store attachment bytes, extracted text, chunks, and generated AI artifacts in
  additive persistence tables separate from provider attachment metadata.
- Cache attachment summaries by task id, prompt version, schema version, model
  id, extraction version, and input fingerprint.

## Scope

The implementation sequence is:

1. Prompt registry and ADR.
2. Existing brief and draft reply migration.
3. Attachment byte store, extraction, chunking, and summary task.
4. Reading-pane Summarize wiring.

V1 attachment support includes PDF text, `text/*`, `text/html`, JSON, and CSV.
DOCX, image OCR, and scanned PDF OCR are explicit follow-up work and must show a
visible unsupported state rather than producing empty summaries.

## Trust Boundary

Raw email bodies, attachment bytes, extracted text, chunks, semantic indexes,
AI summaries, and generated reply drafts stay on device. Team Connect and other
future integrations may receive only user-approved minimized payloads. Logs must
not include raw prompt text, raw model output, attachment contents, email body
text, bearer tokens, refresh tokens, or connector secrets.

## Draft Reply Initiation Policy

Draft reply generation is a user-triggered AI task, not a side effect of
opening or focusing a thread. Reading a thread, showing the inline composer, or
opening the bottom Draft panel may prepare local UI state and may surface an
already-generated cached draft for the same thread, tone, and language, but it
must not start a new `draftReply` model invocation.

Explicit generation entry points are limited to draft-specific user actions:
the brief rail draft CTA, the thread Draft action, the inline composer Generate,
Retry, and Regenerate controls, and existing edit/send flows after a draft
already exists. Tone or reply-language changes may regenerate only after the
user has already requested a draft for the current composer context; before
that first request, the composer must keep showing an explicit ready state.

This policy keeps AI output creation separate from passive mail reading. It
also keeps observability aligned with user intent: privacy-safe `ai.draft_reply`
generated or failed events are emitted only when a draft generation request
actually starts, never when a thread is merely selected.

## Consequences

- Prompt changes become testable and cache-safe.
- Attachment summary invalidation is deterministic.
- Future tasks such as search, classification, and action planning can reuse the
  same task metadata and structured-output execution path.
- The first attachment summary implementation is intentionally narrow; unsupported
  types are product-visible instead of hidden fallbacks.

## Rollback

If attachment summaries block release, disable the Summarize UI and the
AttachmentRAG orchestrator. Leave additive database tables dormant; do not drop
them in a rollback build. The prompt registry can remain if thread brief and
draft reply tests stay green.
