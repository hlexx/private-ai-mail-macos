# Plan: Split AttachmentRAG Attachment Intelligence

## Summary
Split the previous broad Task 5 into smaller, independently validated steps. The
sequence is: build the AttachmentRAG chunking/retrieval core first, then add the
Persistence-backed chunk/artifact cache, then add summary orchestration behind a
local protocol with explicit network-isolation tests. This preserves the
EMAIL_ALF order: Private AI inbox first, attachment intelligence second, Team
Connect integrations later.

Non-goals for this split: no ThreadFeature UI wiring, no Team Connect behavior,
no cloud fallback, no direct feature/UI dependency on AIRuntime, and no new
schema migration unless an existing attachment-processing table is insufficient.

## Impact Checklist
- Business flow: improves local attachment intelligence groundwork; no user-facing
  workflow changes until later ThreadFeature wiring.
- Domain boundaries: AttachmentKit owns extraction; AttachmentRAG owns chunking,
  retrieval, and attachment summary orchestration; AIKit/AIRuntime remain behind
  existing AI abstractions.
- API / contracts: introduces typed AttachmentRAG chunk/retrieval/summary
  contracts and test doubles; no UI-facing API yet.
- Schema / data model: reuses `attachment_chunk` and `attachment_ai_artifact`
  from the existing additive attachment data-plane migration.
- Auth / permissions: no new auth; no external service credentials.
- Cache / queue / async workflow: adds versioned cache keys and deterministic
  local recomputation behavior; no background queue wiring in this plan.
- Observability: add privacy-safe diagnostics only around job state, cache hits,
  and summary status; never log raw attachment text or payloads.
- Migration: no new migration expected; if a schema gap is found, stop and record
  it rather than adding a surprise migration in this split.
- Rollback: revert this plan's commits; the existing attachment schema remains
  unused by later callers if reverted.
- Debt impact: retires the AttachmentRAG namespace stub in small steps; keeps
  embedding/vector search and real LLM summary quality as explicit later choices
  if current local abstractions are insufficient.
- ADR required: no new ADR unless the implementation needs a new schema,
  cloud-fallback, or cross-package AIRuntime public contract change.

## Validation Commands
- `cd Packages/Attachments/AttachmentRAG && swift test`
- `cd Packages/Core/Persistence && swift test`
- `cd Packages/AI/AIKit && swift test`
- `cd Packages/AI/AIRuntime && swift test`
- `git diff --check`

### Task 1: Implement AttachmentRAG Chunking And Retrieval Core
- [x] Replace the `AttachmentRAG` namespace stub with typed contracts for
      `AttachmentChunk`, evidence source references, chunking policy, retrieval
      query, retrieval result, and deterministic cache key inputs.
- [x] Implement a local chunker that consumes `AttachmentExtractionResult` from
      AttachmentKit, preserves page/byte/section evidence locators, drops empty
      sections, and never stores raw text in logs.
- [x] Implement deterministic lexical retrieval over chunks using local scoring
      only. Do not call AIKit, AIRuntime, network APIs, or Persistence in this
      task.
- [x] Add `AttachmentRAGTests` for PDF-page evidence, text byte-range evidence,
      empty/unsupported extraction handling, stable chunk ordering, retrieval
      ranking, and cache-key determinism.
- [x] Run `cd Packages/Attachments/AttachmentRAG && swift test` and fix failures.
- [x] Run `git diff --check` and fix whitespace issues.

### Task 2: Add Persistence-Backed Chunk And Artifact Cache
- [x] Add an AttachmentRAG repository/cache boundary that stores and fetches
      chunks through existing `AttachmentChunkRecord` rows without changing the
      migration.
- [x] Add artifact persistence for attachment summary payloads through existing
      `AttachmentAIArtifactRecord` rows with cache keys based on attachment ID,
      extraction version, chunking policy version, model ID, and prompt version.
- [x] Keep GRDB access behind an AttachmentRAG-owned protocol or small adapter so
      feature/UI code does not depend on record details.
- [x] Add tests covering chunk upsert/fetch, artifact cache hit/miss,
      invalidation when extraction version or policy version changes, and cascade
      assumptions using the existing foreign keys.
- [x] Run `cd Packages/Attachments/AttachmentRAG && swift test` and fix failures.
- [x] Run `cd Packages/Core/Persistence && swift test` and fix failures.
- [x] Run `git diff --check` and fix whitespace issues.

### Task 3: Add Local Attachment Summary Orchestration
- [x] Introduce typed attachment summary output with `summary`, `keyFields`,
      `risks`, `nextSteps`, `evidenceChunkIds`, `modelId`, `promptVersion`, and
      `confidence`.
- [x] Add an AttachmentRAG summarizer protocol and deterministic local test
      implementation. If existing AIKit needs a public extension, keep it narrow
      and do not expose AIRuntime directly to AttachmentRAG callers.
- [x] Implement orchestration that retrieves relevant chunks, calls the summarizer
      protocol, persists the artifact through the Task 2 cache, and returns a
      typed status for complete, incomplete, unsupported, and failed cases.
- [x] Add network-isolation tests proving summary orchestration does not perform
      network access by default and fails closed when a cloud fallback is not
      explicitly configured.
- [x] Add or update AIKit/AIRuntime tests only for changed public contracts; avoid
      broad live-model validation in this split.
- [x] Run `cd Packages/Attachments/AttachmentRAG && swift test` and fix failures.
- [x] Run `cd Packages/AI/AIKit && swift test` and fix failures if AIKit changed.
- [x] Run `cd Packages/AI/AIRuntime && swift test` and fix failures if AIRuntime
      changed.
- [x] Run `git diff --check` and fix whitespace issues.

## Rollback / Recovery
- If Task 1 fails, revert only the AttachmentRAG chunking commit and keep the
  previous Task 1-4 branch state at `8771eb2`.
- If Task 2 fails due to schema mismatch, stop and record the exact missing
  column or index before adding a migration.
- If Task 3 hangs or crosses too many packages, stop after Task 2 and create a
  narrower summary-only plan that does not touch Persistence.

## Notes
- Always run validation from this ralphex worktree, not the dirty main checkout.
- The main checkout may contain unrelated local edits; do not merge, reset, or
  revert them from this plan.
