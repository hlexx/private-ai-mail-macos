# ADR 0001: Startup, Credential, and Label Reconcile Contracts

Date: 2026-05-21

Status: Accepted

## Context

The app opens a local GRDB database at startup, creates Gmail clients from stored
credentials, and reconciles Gmail labels after the label schema migration.
Previously, these paths had implicit failure behavior:

- database open failures could crash through forced startup construction;
- missing Gmail credentials could create an empty credential and let operations
  continue into provider calls;
- label reconciliation cleared its retry flag before proving that all accounts
  reconciled successfully.

These paths affect user-visible mailbox state and the trust boundary between
local optimistic mutations and remote provider calls.

## Decision

- App composition is throwable. Startup failures are surfaced through a recovery
  scene with retry, database path visibility, Finder reveal, and quit actions.
- Gmail API construction uses a throwing factory. Missing credentials fail as
  `AuthError.missingCredential(accountID:)` before local mailbox mutation or
  sync engine startup.
- Label reconciliation is owned by a coordinator in the composition layer. It
  runs at most once concurrently, clears `pam.needsLabelReconcile` only after
  all target accounts succeed, and leaves the flag set for retry on failure.
- App-hosted tests must not start production resume or label-reconcile work
  against the user's local database.

## Consequences

- Startup and credential failures are explicit user-facing errors instead of
  hidden fallbacks or crashes.
- Local state is not mutated when the app cannot build a real provider client.
- Migration cleanup becomes retryable and observable through app toasts and
  unified logging.
- Tests are isolated from background production workflows.

## Rollback

If this contract causes a release blocker, revert the throwing factory and
startup recovery changes as one unit and restore the previous composition
construction. The label reconcile coordinator can be disabled by skipping the
call from `MainScene`, which leaves the retry flag intact for a future fixed
build.
