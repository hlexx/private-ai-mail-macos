# ADR 0005: Trust MVP Gmail and Outlook Provider Contracts

Date: 2026-05-29

Status: Accepted

## Context

Trust MVP 01 establishes architecture gates for adding Outlook support without
breaking the current local-first privacy boundary or hard-coding provider
details into shared layers. The app already runs Gmail flows, but shared mail
contracts need explicit provider-neutral rules before Microsoft Graph adapter
work can proceed safely.

## Decision

- Trust MVP provider scope is Gmail API and Microsoft Graph only.
- Out of scope for this tranche: iCloud, IMAP, JMAP, shared mailboxes,
  delegated mailboxes, team inbox, CRM writes, Slack writes, Notion writes, and
  auto-send.
- Product delivery order is:
  1. reliable sync, search, send, offline behavior, and error recovery;
  2. optional private AI capabilities.
- Local-first trust boundary is mandatory: raw bodies, attachments, drafts,
  local indexes, AI artifacts, and model prompts stay on device unless the user
  explicitly sends email or approves a minimized external payload.
- Provider checkpoint contracts are explicit:
  - Gmail uses History API checkpoints.
  - Microsoft Graph uses per-folder opaque delta URLs.
  - UI and feature modules must not inspect provider-specific checkpoint
    payloads and must operate only on shared checkpoint abstractions.

## Microsoft Graph Source Constraints (Task 1)

Official Microsoft documentation records the following constraints for the
Trust MVP Graph adapter:

- Message delta is scoped to one mail folder at a time. A folder hierarchy sync
  must track every selected folder independently; there is no provider-neutral
  global history cursor equivalent to Gmail History API.
- Graph message delta returns either `@odata.nextLink` while a sync round still
  has more pages, or `@odata.deltaLink` when the current round is complete.
  Both URLs contain provider state tokens, are opaque to the client, and must be
  persisted and replayed as returned for the same account and folder.
- Initial sync and later incremental sync use the same per-folder delta
  endpoint. Query options such as `$select`, `$top`, limited `$filter`,
  limited `$orderby`, and `changeType` are encoded into the returned
  next/delta links by Microsoft Graph, so adapter code must not reconstruct
  those URLs from token fragments.
- Trust MVP uses delegated access only: the signed-in user authorizes the app,
  and the app can act only within both the granted Graph scopes and that user's
  mailbox privileges. Application permissions and app-only daemon access are
  outside the product boundary.
- Least-privilege delegated scopes for Trust MVP are:
  - `Mail.ReadWrite` for reading, creating, updating, moving, marking,
    deleting, and folder-scoped sync/mutation workflows in the signed-in user's
    mailbox. This scope does not grant send permission.
  - `Mail.Send` for sending as the signed-in user and saving the provider copy
    to Sent Items. This scope is requested separately from `Mail.ReadWrite`.
  - `offline_access` for refresh-token based reconnect and background sync after
    the authorization-code flow.
  - `openid`, `profile`, and `email` for account identity. The `email` claim is
    optional in Microsoft identity tokens, so account records must tolerate a
    missing email claim and fall back to a verified profile/mailbox identity
    fetch when auth scaffolding adds that call.
- Shared or delegated mailbox access requires the `Mail.Read.Shared`,
  `Mail.ReadWrite.Shared`, or related shared send scopes and different
  addressing paths. These are non-goals for this MVP.
- Non-goals for the Graph adapter tranche are shared mailboxes, delegated
  mailboxes, application permissions, tenant admin or admin-consent flows,
  calendar, contacts, Teams, OneDrive, SharePoint, enterprise policy UI, and
  Exchange governance controls.

Sources:

- Microsoft Graph: Get incremental changes to messages in a folder:
  https://learn.microsoft.com/en-us/graph/delta-query-messages
- Microsoft Graph permissions reference:
  https://learn.microsoft.com/en-us/graph/permissions-reference
- Microsoft identity platform scopes and OpenID Connect scopes:
  https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc
- Microsoft identity platform permissions and consent overview:
  https://learn.microsoft.com/en-us/entra/identity-platform/permissions-consent-overview
- Microsoft Graph shared and delegated folders:
  https://learn.microsoft.com/en-us/graph/outlook-share-messages-folders

## Gmail-Only Assumptions Kept In Adapter Boundaries (Task 2 Audit)

- `MailProviders/Gmail/*` keeps Gmail DTOs, endpoint wiring, and
  `GmailAPIError` details.
- `AuthKit/GmailOAuthConfig` and Gmail profile fetch endpoints remain
  Gmail-specific until Outlook auth wiring is introduced.
- App composition (`CompositionRoot`) keeps Gmail-specific runtime wiring
  (`GmailOAuthClient`, `GmailAPIClient`, attachment byte provider) outside
  shared domain contracts.
- Settings account onboarding remains Gmail-only (`addGmailAccount`) in this
  tranche; multi-provider account UX is deferred to later Trust MVP steps.
- Label reconciliation and mutation behavior that relies on Gmail system label
  IDs (`INBOX`, `STARRED`, `SENT`, etc.) stays in Gmail-oriented sync components
  until canonical mailbox abstractions land.
- Persistence migrations that backfill Gmail label semantics remain unchanged in
  this tranche; they are tracked for provider-neutral follow-up.

## Consequences

- Shared domain and sync contracts can stay provider-neutral while Gmail and
  Graph adapters keep provider-specific mapping details.
- Release risk is reduced by requiring core reliability outcomes before optional
  AI experience work in this Trust MVP sequence.
- Privacy boundaries remain enforceable across sync, search, send, and future
  provider expansion.

## Rollback

If Outlook work blocks release, keep Microsoft Graph behind a feature flag and
disable Graph runtime paths. Any additive Outlook-related schema fields can stay
dormant and unused in rollback builds. Gmail behavior remains active and
backwards-compatible.
