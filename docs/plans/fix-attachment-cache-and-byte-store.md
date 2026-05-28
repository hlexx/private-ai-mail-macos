# Plan: Fix Attachment Summary Cache And Byte Store Integrity

## Summary

Goal: fix two material attachment-summary integrity issues. A malformed cached attachment summary must not permanently break retries, and the local byte store must not map different attachment identifiers to the same filesystem path. Do not change the database schema, public app UI, model-task architecture, or Gmail permissions. The change must remain backward-compatible with existing `attachment_blob.relative_path` rows: old paths must still load, while newly stored blobs use collision-resistant paths.

## Architecture Decision

- Problem framing: attachment summarization can become stuck on one malformed cached artifact, and two different attachments can collide on disk because path sanitization is lossy.
- Root-cause hypothesis: `AttachmentRAGCache` decodes cached JSON before it can validate or evict the artifact, and `AttachmentByteStore.safePathComponent` replaces multiple different raw identifier characters with `_`.
- Options considered: delete all attachment-summary cache on any decode failure; add a database migration; use reversible escaping; use hash-based path components and validate bytes before extraction.
- Chosen approach: evict only the matching malformed cached artifact and regenerate it; store new blobs under hash-based path components; verify stored blob byte count and SHA-256 before extraction when a cached summary is not usable.
- Why alternatives were rejected: deleting all cache is too broad; a migration is unnecessary because `relative_path` already stores the full path; another lossy sanitizer would keep the collision class alive.
- Risks and trade-offs: already corrupted local files cannot be repaired without fetching attachment bytes again. If no byte provider is available, the orchestrator must fail with a typed unavailable error instead of extracting from untrusted bytes.
- ADR required: no. This is a corrective change inside the existing attachment-summary architecture and does not introduce new shared contracts or persistence schema.

## Impact Checklist

- Business flow: improves reliability and correctness of attachment `Summarize`.
- Domain boundaries: changes are limited to `AttachmentKit` byte storage and `AttachmentRAG` cache/orchestration.
- API / contracts: no public API changes.
- Schema / data model: no migration and no table changes.
- Auth / permissions: no changes.
- Cache / queue / async workflow: malformed cached summaries are evicted and regenerated; corrupt or mismatched blob files are refetched before extraction.
- Observability: add privacy-safe logs for cache decode failure and blob integrity failure. Do not log email bodies, attachment bytes, extracted text, chunk text, model prompts, or model output.
- Migration: existing `relative_path` values continue to load.
- Rollback: reverting the code is safe. New hash-based `relative_path` values are still plain stored paths and can be read by the old loader.
- Debt impact: retires two hidden data-integrity risks without expanding scope.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/.ralphex/worktrees/stabilize-ai-attachments-action-core && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/.ralphex/worktrees/stabilize-ai-attachments-action-core/Packages/Attachments/AttachmentKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/.ralphex/worktrees/stabilize-ai-attachments-action-core/Packages/Attachments/AttachmentRAG && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/.ralphex/worktrees/stabilize-ai-attachments-action-core && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/.ralphex/worktrees/stabilize-ai-attachments-action-core && ! rg -n '(Bearer |refresh_token|client_secret|Logger.*(body|html|payload|attachment)|print\\(.*(body|html|payload|attachment))' Apps Packages --glob '*.swift' --glob '!**/Tests/**' --glob '!**/.build/**'`

### Task 1: Recover from malformed cached attachment summaries

- [x] In `Packages/Attachments/AttachmentRAG/Sources/AttachmentRAG/AttachmentRAGCache.swift`, wrap `JSONDecoder().decode(AIAttachmentSummary.self, ...)` in `do/catch`.
- [x] On decode failure, log only safe metadata: attachment id, task id, prompt version, schema version and failure kind.
- [x] On decode failure, call `deleteCachedSummary(request, fingerprint:)` and return `nil` so the orchestrator regenerates the summary.
- [x] Preserve the existing evidence-validation behavior: invalid evidence still deletes only the matching cached artifact and regenerates.
- [x] Add an `AttachmentRAG` test that seeds an invalid `payloadJSON`, calls `summarize`, proves no throw from the bad cache path, proves the model/provider path is used, and proves the resulting artifact is valid.
- [x] Run `cd Packages/Attachments/AttachmentRAG && swift test` and fix failures.

### Task 2: Make new attachment byte paths collision-resistant

- [x] In `Packages/Attachments/AttachmentKit/Sources/AttachmentKit/AttachmentByteStore.swift`, replace lossy `safePathComponent` path generation for new stores with collision-resistant components, for example `v2/<sha256(accountId)>/<sha256(messageId)>/<sha256(attachmentId)>`.
- [x] Keep `load(relativePath:)` and `delete(relativePath:)` unchanged enough to read old paths already stored in the database.
- [x] Do not add a database migration; `attachment_blob.relative_path` remains the source of truth for already stored files.
- [x] Add an `AttachmentKit` test where two different id sets that previously collapsed to the same sanitized path now produce different `relativePath` values and both files round-trip correctly.
- [x] Keep Time Machine exclusion behavior covered by the existing test.
- [x] Run `cd Packages/Attachments/AttachmentKit && swift test` and fix failures.

### Task 3: Verify stored blob bytes before extraction on cache miss

- [ ] In `Packages/Attachments/AttachmentRAG/Sources/AttachmentRAG/AttachmentRAG.swift`, preserve the existing fast path where a valid cached summary can return without loading attachment bytes.
- [ ] Before extracting text on a cache miss, load bytes through `AttachmentByteStore.load(relativePath:)` and verify `byteCount` and `AttachmentByteStore.sha256Hex(data)` against `AttachmentBlobRecord`.
- [ ] If the file is missing or hash/size mismatch occurs, log safe metadata, remove or replace the stale `attachment_blob` record, and fetch fresh bytes through `byteProvider`.
- [ ] If the file is missing/corrupt and no `byteProvider` is available, return the existing typed unavailable failure rather than extracting from untrusted bytes.
- [ ] Add an `AttachmentRAG` test where a stored blob record points to bytes with the wrong hash; the orchestrator must refetch, replace the blob record, and summarize the fresh bytes.
- [ ] Add or preserve a test proving a valid cached summary still works without network/model execution.
- [ ] Run `cd Packages/Attachments/AttachmentRAG && swift test` and fix failures.

### Task 4: Run final integrity checks

- [ ] Run all validation commands from this plan.
- [ ] Confirm `git diff --check` is clean.
- [ ] Confirm the privacy grep returns no matches.
- [ ] Summarize changed files, tests run, and any remaining risk in the final Ralphex report.

## Rollback / Recovery

- If cache recovery causes a regression, revert only the `AttachmentRAGCache` change; evidence validation and cache keying remain as before.
- If hash-based paths cause a regression, revert only new `AttachmentByteStore.store` path generation. Existing rows keep their explicit `relative_path`, so no database rollback is required.
- If blob integrity validation blocks summaries because bytes cannot be refetched, keep the typed failure visible and do not extract from bytes whose saved hash does not match.

## Notes

- This plan should run against the existing `stabilize-ai-attachments-action-core` worktree because the findings were reviewed there.
- Do not fix unrelated no-op UI actions, action-command schema validation, draft generation, label refresh, or app release packaging in this run.
