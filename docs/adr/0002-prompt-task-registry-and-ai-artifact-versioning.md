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
