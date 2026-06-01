# Trust MVP Sequencing

This document is the app-repo execution sequence for ADR 0005. It keeps the
Gmail and Outlook Trust MVP work ordered around reliability, privacy, and
provider boundaries before expanding optional private AI behavior.

## Current implementation status

- Microsoft Graph network calls: implemented in provider/sync packages but
  product-disabled. Settings still keeps Add Outlook disabled until real-account
  smoke evidence and an ADR-backed mutation plan are complete.
- Full local search: implemented for synced local mail through the local index.
  Provider server search remains explicit and must not silently replace local
  search.
- Send and action queues: implemented for Gmail Trust MVP flows. Gmail send uses
  durable queued send; supervised actions use `action_outbox` for draft reply,
  archive, star, mark read, and trash.
- Attachments: local byte storage, checksum validation, metadata search, narrow
  preview states, and AI summary foundations are implemented. Broad DOCX/OCR,
  archive extraction, and arbitrary attachment preview remain deferred.

## Tranches and release gates

### Tranche 1: Provider contracts and architecture gate

Scope: record the Trust MVP decision, remove Gmail-only assumptions from shared
contracts where safe, and make persistence accept Outlook account rows.

Release gates:

- ADR 0005 is accepted and names scope, rollback, privacy boundary, and
  checkpoint rules.
- `MailDomain` owns provider identifiers and canonical mailbox vocabulary.
- `MailProviders` owns capability and error taxonomy contracts.
- `Persistence` accepts Gmail and Outlook account rows without changing
  existing Gmail data.
- SwiftPM tests for `MailDomain`, `MailProviders`, `MailSync`, and
  `Persistence` pass.

Status: complete for the Trust MVP provider-contract tranche; later provider
work must preserve ADR 0005 boundaries.

### Tranche 2: Outlook auth and account connection

Scope: add Microsoft identity account connection without changing Gmail auth
behavior or weakening token storage boundaries.

Release gates:

- Microsoft Graph delegated scopes are explicit and minimal.
- Account connection UI exposes Gmail and Outlook without provider-specific
  logic leaking into feature stores.
- Tokens remain in the existing secure credential boundary.
- Revocation, expired auth, and insufficient scope map to shared provider error
  categories.

Status: product-disabled. Auth/config scaffolding exists, but account connection
remains gated off in Settings for the release candidate.

### Tranche 3: Graph read adapter and delta sync

Scope: implement Graph message, folder, category, attachment metadata, and
per-folder delta adapters behind a dormant or controlled runtime flag.

Release gates:

- Graph adapter maps messages into `MailDomain` without exposing Graph DTOs to
  UI or feature modules.
- Delta links remain opaque provider checkpoints.
- Folder and category mapping follows the canonical mailbox contract.
- Gmail History API sync behavior is unchanged.

Status: implemented below the product flag. Outlook/Graph read and delta-sync
code exists, but app-level enablement still requires smoke evidence.

### Tranche 4: Provider-neutral sync orchestration and recovery

Scope: make sync orchestration operate through provider contracts while keeping
offline recovery and checkpoint invalidation observable.

Release gates:

- Sync orchestration branches on shared provider capability, not concrete Gmail
  or Graph client types outside the adapter boundary.
- Offline, rate-limit, invalid checkpoint, and provider-unavailable recovery
  paths are tested.
- Progress and recovery logs use privacy-safe account, provider, stage, and
  category fields.

Status: partially implemented. Gmail remains the stable runtime path; Graph sync
coverage exists but is not product-enabled.

### Tranche 5: Full local search

Scope: add provider-neutral local search over synced metadata, bodies, and
supported attachment text while preserving the local-first trust boundary.

Release gates:

- Raw bodies, local indexes, and extracted attachment text stay on device.
- Search ranking and filters do not depend on Gmail labels or Graph folders
  directly.
- Provider server search is optional and explicit, with minimized query payloads
  and no silent fallback from local to server search.

Status: implemented for local synced mail.

### Tranche 6: Send and mutation queue

Scope: add durable queued send and mailbox mutation workflows with provider
capability checks, retry policy, idempotency, and user-visible recovery.

Release gates:

- Draft/send/move/archive/delete/star/flag operations use shared command
  contracts.
- Queue records have durable state transitions, retry limits, conflict handling,
  and cancellation semantics.
- Auto-send remains out of scope unless a later ADR changes the trust boundary.

Status: implemented for Gmail send and the Trust MVP action layer. Outlook
mutations, Snooze, automatic rules, Slack/Notion/CRM writes, cloud broker
delivery, and model-router action tasks remain deferred.

### Tranche 7: Attachments data plane and broad preview

Scope: finish provider-neutral attachment download, byte storage, extraction,
preview, and AI-summary handoff across Gmail and Outlook.

Release gates:

- Attachment bytes stay local unless the user explicitly sends mail or approves
  a minimized external payload.
- Gmail and Graph attachment fetchers satisfy the same attachment contract.
- Preview support covers the agreed high-frequency file types, with unsupported
  types handled visibly and safely.
- AI artifact generation uses local extracted text and versioned prompts.

Status: partially implemented. Local storage, checksum validation, metadata
search, limited preview state, and AI-summary foundations are present; broad
preview, DOCX/OCR, and archive extraction are not complete.

### Tranche 8: Trust MVP release hardening

Scope: verify the end-to-end Gmail and Outlook release candidate across account
connection, read, sync, search, send, attachments, offline use, and error
recovery.

Release gates:

- Both providers pass smoke tests for connection, initial sync, incremental
  sync, search, send, mutation, attachment fetch, offline recovery, and auth
  recovery.
- Privacy review confirms raw bodies, attachments, drafts, indexes, AI
  artifacts, and prompts remain local unless the user takes an explicit external
  action.
- Observability covers provider, account hash or local account id, operation,
  stage, shared error category, retry count, and checkpoint state without raw
  message content.
- Rollback can disable Graph paths while preserving Gmail and leaving dormant
  Outlook-compatible schema intact.

Status: automated gate implemented in `scripts/verify-trust-mvp.sh`; live Gmail
and Outlook smoke evidence plus notarized packaging remain release-owner manual
work.

## EMAIL_ALF follow-up

Do not edit `../EMAIL_ALF` from this app implementation plan. After the app-side
contracts and validation are complete, update these product documentation files
in a separate EMAIL_ALF change:

- `../EMAIL_ALF/04_product_requirements.md`
- `../EMAIL_ALF/07_architecture.md`
- `../EMAIL_ALF/08_security_privacy.md`
- `../EMAIL_ALF/10_roadmap.md`
