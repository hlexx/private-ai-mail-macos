# Plan: Step 15 — Private AI Inbox, Attachment Intelligence, Team Connect Sequencing

## Summary

Align the next development tranche with `EMAIL_ALF`: finish the app as a credible
Private AI inbox first, add real attachment intelligence second, and only then
wire Team Connect integrations through explicit preview/approval boundaries.
This plan is intentionally sequence-heavy: do not start Slack/Notion write
paths until inbox state, attachment extraction, and minimized action payloads are
observable and testable. Keep raw email bodies, attachments, local indexes, AI
artifacts, and reply drafts on device. P1 SQLite page encryption remains out of
scope for MVP by product decision; FileStore/encrypted-at-rest work is still in
scope for attachments.

Source-of-truth docs:

- `/Users/alexeykhaynovsky/Documents/Projects/Re_Box/EMAIL_ALF/04_product_requirements.md`
- `/Users/alexeykhaynovsky/Documents/Projects/Re_Box/EMAIL_ALF/08_security_privacy.md`
- `/Users/alexeykhaynovsky/Documents/Projects/Re_Box/EMAIL_ALF/10_roadmap.md`
- `/Users/alexeykhaynovsky/Documents/Projects/Re_Box/EMAIL_ALF/14_macos_app_design.md`

Current baseline verified 2026-05-22:

- `MailSync`, label graph, persistent `thread_brief`, `AIService.draftReply`,
  inline composer, and most real-data inbox work exist.
- `AttachmentKit`, `AttachmentRAG`, `IntegrationDomain`,
  `IntegrationBroker`, and `IntegrationConnectors` are still mostly namespace
  stubs.
- `ActionSheetView` is visual/demo-oriented and still describes actions with
  static copy instead of typed minimized payloads, approval state, retry status,
  and idempotency.

## Impact Checklist

- Business flow: strengthens account connection, daily inbox use, attachment
  understanding, then paid Team Connect workflows.
- Domain boundaries: keeps mailbox state in Mail packages, attachment
  extraction in Attachments packages, AI summarization in AI packages, and
  external workflow payloads in Integrations packages.
- API / contracts: adds attachment extraction/RAG contracts and supervised
  integration action contracts; keeps `AIService` as the only AI feature
  protocol exposed to features.
- Schema / data model: adds attachment extraction/chunk/artifact/action/audit
  tables; migrations must be additive and idempotent.
- Auth / permissions: no new mail provider scopes unless an action requires it;
  Team Connect connector tokens are not stored in this macOS app beyond local
  development stubs.
- Cache / queue / async workflow: adds attachment processing queue,
  AI artifact cache, integration action queue/status model, and retry-safe
  idempotency keys.
- Observability: add OSLog categories for AttachmentExtraction, AttachmentRAG,
  ActionPreview, IntegrationDispatch, and privacy-safe failure states. Never log
  raw body text, attachment content, bearer tokens, refresh tokens, or generated
  full payload bodies.
- Migration: additive GRDB migrations only; no destructive cleanup of existing
  mail tables in this step.
- Rollback: gate new attachment processing and Team Connect dispatch from
  `CompositionRoot`/feature flags; if a migration ships, leave new tables unused
  rather than dropping them.
- Debt impact: retires attachment and integration namespace stubs; introduces
  deliberate preview-only connector stubs until broker deployment exists.
- ADR required: yes. This touches schema, background jobs, external payload
  trust boundaries, and paid workflow architecture.

## Validation Commands

- `PROJ=/Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos`
- `cd $PROJ && tuist generate`
- `cd $PROJ && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd $PROJ && xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MacAppTests`
- `cd $PROJ/Packages/Core/Persistence && swift test`
- `cd $PROJ/Packages/Mail/MailSync && swift test`
- `cd $PROJ/Packages/AI/AIKit && swift test`
- `cd $PROJ/Packages/AI/AIRuntime && swift test`
- `cd $PROJ/Packages/AI/AIEvals && swift test`
- `cd $PROJ/Packages/Attachments/AttachmentKit && swift test`
- `cd $PROJ/Packages/Attachments/AttachmentRAG && swift test`
- `cd $PROJ/Packages/Integrations/IntegrationDomain && swift test`
- `cd $PROJ/Packages/Integrations/IntegrationBroker && swift test`
- `cd $PROJ/Packages/Features/ActionsFeature && swift test`
- `cd $PROJ/Packages/Features/ThreadFeature && swift test`
- `cd $PROJ/Packages/Features/BriefFeature && swift test`
- `cd $PROJ && git diff --check`
- `cd $PROJ && ! rg -n '(Bearer |refresh_token|client_secret|Subject:.*\\(|print\\(.*(body|html|payload|attachment)|Logger.*(body|html|payload|attachment)|os_log.*(body|html|payload|attachment))' Apps Packages --glob '*.swift' --glob '!**/Tests/**' --glob '!**/.build/**'`

### Task 1: Record the sequencing contract and guardrails

- [ ] Create `docs/adr/0002-private-inbox-attachment-team-connect-sequencing.md`.
- [ ] In the ADR, state the sequence: Private AI inbox first, Attachment
      Intelligence second, Team Connect integrations third.
- [ ] In the ADR, explicitly preserve the `EMAIL_ALF` trust boundary: raw
      email bodies, attachments, semantic indexes, AI artifacts, and reply
      drafts stay on device; Team Connect sends only user-approved minimized
      payloads.
- [ ] In the ADR, state non-goals for this tranche: SQLCipher, CRM writes,
      Salesforce, enterprise governance, multi-device sync, and auto-send.
- [ ] Add a short `README.md` / `NOTES.md` update only if the current text says
      the integration or attachment capability is already complete when it is
      not.
- [ ] Run `cd $PROJ && git diff --check`.

### Task 2: Harden the Private AI inbox baseline before attachment work

- [ ] Audit current mailbox actions from UI to provider: archive, unarchive,
      star, unstar, read/unread, trash/untrash, send, refresh, account reconnect.
      Document any remaining no-op or demo-only path in this plan or a follow-up
      issue before starting Team Connect.
- [ ] Add a small domain-level `MailboxAction` or equivalent use-case contract
      only if existing `MailMutator` call sites are duplicating provider/local
      mutation logic. Keep the abstraction in Mail/Feature boundary, not in UI.
- [ ] Ensure each mailbox action resolves a real provider client before local
      optimistic mutation; missing credentials must fail before changing SQLite.
- [ ] Add/extend tests in `Packages/Mail/MailSync/Tests/MailSyncTests` for
      provider-factory failure, provider API failure rollback, and idempotent
      repeated mutations.
- [ ] Ensure user-visible errors distinguish missing credential, provider
      rejection, rate limit, and offline/degraded sync.
- [ ] Add privacy-safe OSLog entries for mutation start/success/failure using
      account/thread hashes or IDs only, never subject/body.
- [ ] Run `cd $PROJ/Packages/Mail/MailSync && swift test`.
- [ ] Run `cd $PROJ && xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MacAppTests`.

### Task 3: Add attachment data-plane schema and storage policy

- [ ] Extend `Persistence` with additive migrations for attachment processing:
      `attachment_extraction`, `attachment_chunk`, `attachment_ai_artifact`, and
      `attachment_processing_job` tables, or equivalent names that match local
      conventions.
- [ ] Keep existing `attachment` rows as provider metadata. Do not overload
      `AttachmentRecord.dataBase64` as the long-term file store for large
      attachments.
- [ ] Add a FileStore-facing abstraction in `AttachmentKit` that can store,
      read, and delete attachment bytes by `(account_id, message_id,
      attachment_id)` while allowing later per-account encryption keys.
- [ ] Exclude attachment byte cache from Time Machine by default where the
      FileStore path is created.
- [ ] Add cascade behavior for account removal: attachment extraction rows,
      chunks, AI artifacts, processing jobs, and FileStore blobs must be removed
      or made unreachable by account deletion.
- [ ] Add `PersistenceTests` covering migration, round-trip, cascade delete,
      and idempotent rerun semantics.
- [ ] Run `cd $PROJ/Packages/Core/Persistence && swift test`.
- [ ] Run `cd $PROJ/Packages/Attachments/AttachmentKit && swift test`.

### Task 4: Implement AttachmentKit extraction for MVP file types

- [ ] Replace the `AttachmentKit` namespace stub with typed contracts:
      `AttachmentExtractor`, `AttachmentExtractionInput`,
      `AttachmentExtractionResult`, `AttachmentExtractionFailure`, and evidence
      locators.
- [ ] Implement PDF text extraction with page references using platform APIs
      available to the macOS target.
- [ ] Implement text/HTML/plain document extraction for text-based docs already
      present in MIME data.
- [ ] Add a DOCX/text-based-doc path if a lightweight parser exists in the
      workspace; otherwise add a clearly typed unsupported state with user-facing
      reason and do not fake extraction.
- [ ] Add image-scan/OCR as optional: use Vision where available; unsupported
      or low-confidence OCR must produce an incomplete extraction state, not an
      empty "success".
- [ ] Keep every result evidence-backed: page number, byte/source range, or
      section locator where possible.
- [ ] Add tests with small fixtures for PDF, plain text, unsupported binary,
      incomplete extraction, and OCR-disabled behavior.
- [ ] Run `cd $PROJ/Packages/Attachments/AttachmentKit && swift test`.

### Task 5: Build AttachmentRAG and AI attachment summaries

- [ ] Replace the `AttachmentRAG` namespace stub with chunking and retrieval
      contracts: `AttachmentChunker`, `AttachmentRetriever`,
      `AttachmentSummaryInput`, and `AttachmentSummaryResult`.
- [ ] Reuse existing AI abstractions. Prefer extending `AIService` only if the
      feature layer needs a stable `attachmentSummary` entry point; do not let
      UI call `AIRuntime` directly.
- [ ] Store attachment chunks and summary artifacts in the new Persistence
      tables with model/version/generated-at metadata.
- [ ] Add cache invalidation keyed by attachment ID + extraction version +
      model/prompt version.
- [ ] Ensure summaries include `summary`, `keyFields`, `risks`, `nextSteps`,
      `confidence`, and `evidence` locators.
- [ ] Add AI eval fixtures for attachment-heavy threads in `Packages/AI/AIEvals`
      or a package-local test corpus, with schema-validity and hallucination
      checks.
- [ ] Add network-isolation tests proving attachment summary generation does not
      make HTTP calls unless a user-enabled cloud fallback is explicitly active.
- [ ] Run `cd $PROJ/Packages/Attachments/AttachmentRAG && swift test`.
- [ ] Run `cd $PROJ/Packages/AI/AIKit && swift test`.
- [ ] Run `cd $PROJ/Packages/AI/AIRuntime && swift test`.

### Task 6: Surface attachment intelligence in ThreadFeature

- [ ] Add a real attachment section in `ThreadView` that shows provider
      attachment metadata, extraction status, preview availability, summary
      status, and evidence links.
- [ ] Use Quick Look for safe local previews when bytes are available. If bytes
      are not yet downloaded, show an explicit download/extract state.
- [ ] Add an `AttachmentSummaryPanel` or equivalent view that displays summary,
      extracted fields, risks, evidence locators, and incomplete/unsupported
      states.
- [ ] Do not show "Ask about attachment" or workflow actions as enabled unless
      they have a real handler and state model.
- [ ] Add a background processing trigger: opening a thread with attachments
      queues extraction; opening a specific attachment prioritizes that job.
- [ ] Add cancellation/backpressure so opening many threads does not start
      unbounded AI or OCR work.
- [ ] Add ThreadFeature tests for no attachment, pending extraction, successful
      extraction, unsupported attachment, failed extraction, and evidence link
      rendering.
- [ ] Run `cd $PROJ/Packages/Features/ThreadFeature && swift test`.
- [ ] Run `cd $PROJ && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.

### Task 7: Define supervised Team Connect action contracts without SaaS writes

- [ ] Replace static action preview text in `ActionsFeature` with typed action
      proposals from `IntegrationDomain`: action kind, source thread,
      minimized payload, data classification, evidence, approval requirement,
      idempotency key, and status.
- [ ] Add `IntegrationDomain` models for Slack update, Notion page/task, and
      later CRM notes, but implement only Slack/Notion preview paths in this
      tranche.
- [ ] Add an `ActionPreviewPolicy` that refuses payloads containing raw thread
      body, full attachment text, full attachment bytes, bearer tokens, or
      refresh tokens.
- [ ] Add `IntegrationActionRecord` and `IntegrationAuditRecord` persistence
      if action status must survive restart; keep payload minimized.
- [ ] Update `ActionSheetView` to show "This will be sent" and "This will NOT
      be sent" sections, matching `EMAIL_ALF/08_security_privacy.md`.
- [ ] Keep "Do it" disabled until preview is valid and user approval is
      explicit.
- [ ] Add tests in `IntegrationDomainTests` and `ActionsFeatureTests` for
      payload minimization, approval gating, idempotency-key stability, and UI
      disabled states.
- [ ] Run `cd $PROJ/Packages/Integrations/IntegrationDomain && swift test`.
- [ ] Run `cd $PROJ/Packages/Features/ActionsFeature && swift test`.

### Task 8: Add Team Connect broker seam with safe stubs

- [ ] Replace the `IntegrationBroker` namespace stub with a protocol:
      `IntegrationDispatching` or similar, returning submitted/queued/failed
      status without exposing SaaS-specific clients to feature modules.
- [ ] Implement a local `PreviewOnlyIntegrationDispatcher` that records audit
      events and returns a non-sent status. Use it by default until real broker
      endpoint, auth, and deployment are configured.
- [ ] Add a real HTTP dispatcher only behind explicit configuration. It must
      accept minimized payloads only and must reject raw email/attachment fields
      before network submission.
- [ ] Add retry and idempotency behavior at the dispatcher boundary; retries
      must not duplicate SaaS objects.
- [ ] Add OSLog events for action preview created, approval granted, dispatch
      queued, dispatch failed, and dispatch completed. Logs must not contain
      payload body text.
- [ ] Add tests for preview-only mode, missing broker config, HTTP rejection of
      unsafe payloads, idempotent retry, and privacy grep.
- [ ] Run `cd $PROJ/Packages/Integrations/IntegrationBroker && swift test`.
- [ ] Run `cd $PROJ && ! rg -n '(Bearer |refresh_token|client_secret|Subject:.*\\(|print\\(.*(body|html|payload|attachment)|Logger.*(body|html|payload|attachment)|os_log.*(body|html|payload|attachment))' Apps Packages --glob '*.swift' --glob '!**/Tests/**' --glob '!**/.build/**'`.

### Task 9: Wire end-to-end UI flow in MacApp composition

- [ ] Register attachment extraction/RAG services in `CompositionRoot`; keep
      service construction throwable where credentials/config can fail.
- [ ] Register integration preview/dispatch services in `CompositionRoot` with
      preview-only dispatcher as default.
- [ ] Ensure app startup remains offline-capable: missing broker config must
      not block reading local mail, local AI, or attachment summaries.
- [ ] Add user-visible status for attachment processing and Team Connect
      preview/dispatch without modal dead ends.
- [ ] Add Settings/Privacy copy explaining local attachment analysis and
      integration payload preview.
- [ ] Add a manual smoke checklist to `NOTES.md` covering: Gmail sync, archive,
      AI brief, attachment preview, attachment summary with evidence,
      Slack/Notion preview-only action, and privacy grep.
- [ ] Run `cd $PROJ && tuist generate`.
- [ ] Run `cd $PROJ && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- [ ] Run `cd $PROJ && xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MacAppTests`.

### Task 10: Final validation and real-data acceptance pass

- [ ] Run every command in `## Validation Commands`; fix failures rather than
      narrowing the validation set.
- [ ] On a real Gmail account, verify: inbox still opens offline after a cached
      sync, archive/star/read/trash actions reconcile with Gmail, and missing
      credentials surface as reconnect-required rather than local mutation.
- [ ] On a real thread with a PDF or text attachment, verify: preview opens,
      extraction status is visible, summary is evidence-backed, unsupported
      states are honest, and no network calls are made for local AI inference.
- [ ] On a real thread, open Team Connect action sheet and verify Slack/Notion
      previews show minimized payloads, "will not send" copy, approval gating,
      idempotency key, and preview-only non-sent status.
- [ ] Run the privacy grep again after the manual smoke to ensure no debug
      logging or fixture escaped into production Swift files.
- [ ] Update release notes or `NOTES.md` with limitations that remain true:
      preview-only integrations until broker deployment, unsupported attachment
      file types, and no CRM writes.

## Rollback / Recovery

- If attachment schema migrations break startup, keep the migration additive and
  fix forward. Do not drop tables in a hot rollback unless there is no shipped
  user data.
- If extraction or AI summary is too slow, disable the background queue from
  `CompositionRoot` and leave manual preview available; existing mail reading
  must remain usable.
- If Team Connect preview leaks too much data, disable `ActionSheetView`
  dispatch entirely and keep the minimized payload policy tests as the blocker.
- If broker config is missing or invalid, the app must remain a local Private AI
  inbox; Team Connect status should be "not configured", not a startup failure.

## Notes

- Preserve the `EMAIL_ALF` monetization sequence. Do not implement CRM or
  Salesforce before Slack/Notion preview + approval is correct.
- Do not add hidden cloud AI fallback while implementing attachment summaries.
  Any cloud fallback must be explicit, user-enabled, and outside this tranche.
- Do not make no-op buttons look successful. Disabled, pending, unsupported,
  and preview-only states must be visible.
