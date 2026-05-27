# ADR 0004: Supervised Action Execution Core

Date: 2026-05-27

Status: Accepted

## Context

Thread briefs, draft replies, and attachment summaries are becoming reliable
enough to support workflow actions, but turning local AI output into real mail,
CRM, Slack, Notion, or destructive mailbox changes crosses a higher trust
boundary. The app needs a durable action contract before UI affordances or Team
Connect providers can execute anything outside the local reading experience.

This ADR follows ADR 0002 and ADR 0003. The required implementation sequence is:

1. Stabilization first: Gmail sync checkpoints, attachment artifact lifecycle,
   prompt input budgets, attachment evidence grounding, and privacy-safe
   logging must be stable.
2. Action core second: define typed action commands, policy and approval
   semantics, local outbox persistence, results, and audit records.
3. UI wiring third: expose only supported and policy-gated actions from thread
   and action surfaces.
4. Team Connect providers last: Slack, Notion, CRM, and broker delivery can use
   the action core only after local contracts are stable.

## Decision

Add a supervised action execution core with this pipeline:

`ActionCommand -> Policy/Approval -> Local Outbox -> Executor -> Result/Audit`

The action domain owns command shape, target identity, payload envelope,
approval requirement, approval state, lifecycle status, failure classification,
result metadata, and audit events. Persistence owns durable outbox, attempt, and
audit tables. Executors are separate from command construction and must not be
bypassed by UI or provider code.

Action identity must include:

- `op_id`: local operation id for the action record.
- `account_id`: mailbox account that owns the local context.
- Target ids: stable thread, message, attachment, or integration destination
  identifiers needed by the action kind.
- Action kind: stable typed action enum value.
- Schema version: payload and result contract version.
- Idempotency key: stable local key for the same user action, without raw body
  text, attachment text, prompt content, model output, or secrets.
- Approval state: not required, pending, approved, rejected, or expired.
- Status: pending, ready, executing, succeeded, failed, cancelled, or blocked.
- Attempt count: total execution attempts recorded for the action.
- Created and updated timestamps.
- Optional external result id: provider or broker result identifier after a
  successful external write.

## Trust Boundary

Raw email bodies, attachments, extracted text, local indexes, prompts, model
output, and generated drafts stay on device unless the user explicitly sends or
approves a minimized payload. Local persistence may store sensitive payload and
result JSON for on-device action execution, but logs, analytics, audit metadata,
test fixtures, idempotency keys, and external provider requests must use
privacy-safe identifiers or minimized user-approved content.

Bearer tokens, refresh tokens, OAuth client secrets, connector secrets, raw
prompt bodies, raw model output, raw email bodies, attachment bytes, and raw
extracted text must not be logged.

## Approval Levels

- Local low-risk actions: mailbox-only non-destructive mutations such as
  archive, star, mark read, or local draft creation may run with no extra
  approval when they originate from an explicit user action.
- Send-mail actions: sending or replying to email requires explicit user
  approval of the final recipient list, subject, and body before execution.
- External writes: Slack, Notion, CRM, broker, or other SaaS writes require a
  preview and explicit confirm before sending a minimized payload.
- Destructive actions: trash, delete, purge, or irreversible mailbox/provider
  changes require explicit confirm and must remain auditable.
- Sensitive legal, finance, HR, or similarly high-impact actions require
  explicit confirm and must not be executed automatically from model output or
  rules.

Policy evaluation decides the default approval requirement from action kind,
target, payload class, account context, and sensitivity flags. Approval state is
stored with the action and must be checked by the executor before side effects.

## Options Considered

1. UI-driven direct execution - rejected because it would couple buttons to
   provider side effects, make approval inconsistent, and bypass durable audit.
2. Model-routed automatic actions - rejected for this plan because action
   routing from model output is a separate trust problem and would blur the
   boundary between suggestion and execution.
3. Local supervised outbox - accepted because it creates a durable contract for
   approval, idempotency, retries, observability, rollback, and future provider
   adapters without requiring external writes now.

## Consequences

- Workflow actions get a single contract before any provider calls are added.
- UI surfaces can render unsupported or blocked actions visibly instead of
  relying on hidden fallbacks.
- Executors can enforce idempotency and approval state consistently.
- Audit records become privacy-safe lifecycle evidence, not a copy of mailbox
  content.
- The local database will gain dormant additive action tables before external
  delivery exists.
- Provider adapters remain deferred and must use the action contract rather than
  inventing their own payload, approval, retry, or audit semantics.

## Out of Scope

This plan does not add Slack, Notion, or CRM provider calls. It does not add
cloud broker delivery, new OAuth scopes, automatic external writes, an
action-router model task, external connector auth, automatic rules, attachment
Preview, DOCX/OCR extraction, or notarized release packaging.

Unsupported or unwired actions must be visibly disabled, dormant, or explicitly
deferred.

## Impact Checklist

- Business flow: prepares currently decorative workflow actions to become real
  supervised actions after stabilization and before provider wiring.
- Domain boundaries: `IntegrationDomain` owns action contracts and policy
  semantics; `Persistence` owns outbox, attempts, and audit records; UI and
  provider modules consume those contracts instead of defining parallel action
  shapes.
- API / contracts: introduces stable action identity, payload, status,
  approval, result, failure, and audit contracts without removing existing mail
  or AI APIs.
- Schema / data model: future action tables are additive and may remain dormant
  if execution is disabled.
- Auth / permissions: no new Gmail, Slack, Notion, CRM, broker, or SaaS scopes
  are introduced by this ADR or the current plan.
- Cache / queue / async workflow: adds a local outbox as the action queue and
  keeps external delivery out of scope until executors and providers are wired.
- Observability: lifecycle logs and audit metadata must be privacy-safe and
  must not include raw mailbox, prompt, model, attachment, token, or secret
  content.
- Migration: action persistence must use additive GRDB migrations; shipped
  tables are not dropped during rollback.
- Rollback: if action execution blocks release, leave additive action tables
  dormant and disable UI entry points or executors.
- Debt impact: retires empty integration namespaces and prevents one-off action
  execution paths; introduces dormant local action infrastructure that future UI
  and provider work must complete.

## Rollback

If action execution blocks release, leave any additive action tables in place,
disable UI entry points and executors, and keep provider adapters unwired. If a
domain contract needs revision before shipping external actions, migrate forward
with a new schema version rather than rewriting historical outbox rows.
