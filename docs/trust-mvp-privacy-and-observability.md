# Trust MVP Privacy and Observability

This document is the product and engineering contract for Trust MVP privacy
copy, settings UI, and privacy-safe observability. It keeps the app local-first:
mailbox content is synchronized for local use, provider operations are limited to
the connected mail providers, and operational logs must never become a mailbox
mirror.

## Default Boundary

No mailbox mirroring by default.

The app does not copy mailbox bodies, attachment bytes, drafts, search indexes,
AI artifacts, prompts, provider cursors, or raw provider responses to the app's
cloud by default. Local state exists to make the signed-in user's mail client
work on this Mac.

Exact exceptions are limited to:

- Provider API calls for sync and send through the user's connected Gmail or
  Microsoft Graph account. This includes read, folder/label mutation, attachment
  byte fetch, and send operations that are required for the user's requested mail
  workflow.
- Future approved integrations that have an explicit product owner, user-visible
  approval, minimized payload definition, observability review, rollback path,
  and ADR 0005 update when mailbox data leaves the device boundary.

No other service, control plane, telemetry sink, analytics pipeline, AI backend,
or support workflow may receive mailbox content by default.

## Data Classes

| Data class | Examples | Storage and movement boundary |
| --- | --- | --- |
| Local raw mail | Message bodies, HTML, snippets, subjects, headers, participants, thread/message ids, labels, read/star/archive state. | Stored in the local mail database for synced accounts. Sent only to Gmail or Microsoft Graph as part of provider API calls needed for sync, mutation, or send. Not mirrored to the app cloud. |
| Local attachments | Attachment metadata, cached bytes, extracted text, previews, hashes, byte counts, cache state. | Metadata and fetched bytes stay in local persistence and local cache paths. Bytes leave the device only when originally fetched from the provider or when a future approved integration explicitly covers the payload. |
| Local drafts | Draft body text, HTML, recipients, queued outgoing body snapshots, idempotency keys, retry state. | Stored locally until the user sends or cancels. On send, the payload goes to the selected provider send API. Draft bodies are not uploaded to app cloud storage. |
| Local indexes | Search tokens, normalized terms, result references, attachment metadata markers, local ranking hints. | Derived and stored locally for on-device search. Query text and index contents are not telemetry payloads. |
| Local AI artifacts | Local prompt inputs, local model outputs, summaries, extracted evidence, model task metadata, prompt versions, cache records. | Remain on device while AI mode is local-only. Cloud AI fallback may use only an approved external payload after the user has enabled that mode and the payload is documented. |
| Provider API requests | Gmail API and Microsoft Graph requests, OAuth re-consent calls, sync checkpoints, send requests, attachment download requests. | Sent to the connected provider only for user-authorized mail workflows. Access tokens, refresh tokens, provider cursors, and provider URLs with embedded state are secret or sensitive and must not be logged. |
| Optional cloud/control-plane metadata | Account id or hash, provider, operation, status, duration, error category, counts, feature flags, app version, schema version. | May be used for privacy-safe diagnostics only after the event contract excludes raw content and secrets. If exported off device, the export path needs a feature flag, owner, rollback path, and ADR 0005 review. |
| Approved external payloads | User-sent email payloads to Gmail or Microsoft Graph, and any future integration payload explicitly approved by product and architecture review. | Must be minimized to the workflow, visible to the user when appropriate, documented before launch, and removable through a rollback plan. |

## Provider API Use

Gmail and Microsoft Graph are the only provider boundaries in the Trust MVP
provider contract. Provider calls are allowed for:

- Syncing mailbox state into local persistence.
- Applying user-requested mail mutations such as archive, star, read/unread,
  trash, label, folder, and related provider actions.
- Fetching attachment bytes into the local cache for supported user-visible
  workflows.
- Sending messages and replies that the user has approved.
- Re-consent and token refresh required to keep those workflows authorized.

Provider calls are not permission to export copies of mailbox data to an app
backend.

## Observability Contract

Logs may contain:

- Account id or hash.
- Provider.
- Operation.
- Status.
- Duration.
- Error category.
- Counts.
- Feature flags.

Logs must not contain:

- Raw mail body, HTML body, snippets, subject text, raw MIME, quoted replies, or
  rendered message content.
- Recipient lists, sender display names, contact names, calendar details, or
  mailbox addresses unless the value is already the approved local account id.
- Attachment bytes, extracted attachment text, attachment previews, attachment
  filenames, or document contents.
- AI prompts, prompt context, model inputs, model outputs, summaries, or
  extracted evidence text.
- OAuth access tokens, refresh tokens, bearer tokens, authorization codes,
  client secrets, cookies, API keys, provider checkpoint tokens, Graph delta
  links, Gmail history payloads, or provider URLs with embedded state.
- Raw provider request or response payloads.
- Local search query text or local index contents.

When a component needs more detail for debugging, it should add a structured
privacy-safe field such as count, size bucket, capability flag, retry number,
elapsed duration, or sanitized failure category instead of logging content.

## UI Copy Requirements

Settings privacy copy should communicate:

- What stays local: raw mail cache, attachments, drafts, indexes, and local AI
  artifacts.
- What goes to providers: Gmail or Microsoft Graph requests needed for sync,
  re-consent, attachment fetch, mutation, and send.
- What is not mirrored: mailbox contents, drafts, indexes, attachment bytes, and
  AI artifacts are not copied to the app cloud by default.
- Which AI mode is active. Unsupported AI controls must not be shown as toggles.
- How cache deletion and account removal affect local mail, attachment bytes,
  indexes, drafts, queues, and AI artifacts.

## Local Cache Deletion and Account Removal

Removing an account is a local deletion operation. It does not delete mail from
Gmail or Microsoft Graph, and it does not send mailbox contents to the app
cloud.

The app must stop sync for the account, delete the locally stored provider
credential, delete the account's attachment byte-cache directory, and remove the
account row from the local database. The database account deletion is the root
of the persistence cascade for:

- Raw local mail rows: sync state, threads, messages, labels, thread labels,
  trusted sender rows, and attachment metadata.
- Local attachment state: blob metadata, extraction records, extracted chunks,
  processing jobs, and attachment AI artifacts.
- Local indexes: search documents and FTS rows derived from the account's
  messages.
- Local drafts and send state: draft rows and queued outgoing message rows,
  including local body snapshots and retry metadata.
- Local AI artifacts: thread brief cache rows and attachment summary artifacts
  tied to the account.
- Provider sync metadata: provider checkpoints such as Graph delta checkpoint
  rows.

If attachment byte-cache deletion fails, account removal should surface a
failure and be retryable rather than silently leaving cached attachment bytes on
disk.

## Change Control

Any change that exports mailbox content, attachment bytes, draft bodies, local
indexes, AI prompts, or AI outputs outside the device or connected provider
boundary requires architecture review before implementation. If telemetry leaves
the device, ADR 0005 must be updated before launch.
