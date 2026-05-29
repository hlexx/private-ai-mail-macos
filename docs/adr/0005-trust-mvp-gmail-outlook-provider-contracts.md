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
