# Trust MVP Outlook Action Readiness

Date: 2026-06-01

## Decision

Outlook is not ready to receive the Trust MVP action executor in the product runtime yet.
Keep Outlook action mutations disabled until account connection, sync orchestration, action execution, and local reconciliation are wired behind provider-neutral boundaries and covered by an ADR-backed implementation plan.

## Current Capability

| Area | Current state | Evidence |
| --- | --- | --- |
| Auth scopes | Microsoft OAuth scope configuration exists for `openid`, `profile`, `email`, `offline_access`, `Mail.ReadWrite`, and `Mail.Send`. | `Packages/Auth/AuthKit/Sources/AuthKit/MicrosoftOAuthConfig.swift` |
| Account connection | Outlook is shown as beta-disabled. `addAccount(provider: .outlook)` returns an error instead of authorizing. Re-consent is also disabled. | `Packages/Features/SettingsFeature/Sources/SettingsFeature/AccountsTabStore.swift` |
| App composition | Runtime composition instantiates `GmailOAuthClient`, a `GmailAPIFactory`, Gmail-only sync, Gmail action execution, Gmail attachment byte provider, and Gmail-only send provider registration. | `Apps/MacApp/Sources/CompositionRoot.swift` |
| Sync | `GraphMailSyncEngine` supports per-folder Graph delta sync and persists opaque per-folder checkpoints, but it defaults to disabled and is not routed by `SyncSupervisor`. | `Packages/Mail/MailSync/Sources/MailSync/GraphMailSyncEngine.swift`, `Packages/Mail/MailSync/Sources/MailSync/SyncSupervisor.swift` |
| Provider API | `GraphAPI` and `GraphAPIClient` expose folder/message delta, attachment fetch, send, mark read, move, archive, trash, flag, and category mutation methods. | `Packages/Mail/MailProviders/Sources/MailProviders/Graph/GraphAPI.swift`, `Packages/Mail/MailProviders/Sources/MailProviders/Graph/GraphAPIClient.swift` |
| Send | `GraphSendExecutor` exists behind `MailSendProvider`, but the app compose runtime registers only `LazyGmailSendProvider`. | `Packages/Mail/MailProviders/Sources/MailProviders/SendExecution.swift`, `Apps/MacApp/Sources/CompositionRoot.swift` |
| Action execution | The active action executor is `GmailActionExecutor`. There is no Outlook/Graph `ActionExecuting` adapter, no action outbox routing by provider, and no Outlook local reconciliation path after mutation. | `Packages/Mail/MailSync/Sources/MailSync/GmailActionExecutor.swift`, `Apps/MacApp/Sources/CompositionRoot.swift` |
| Draft creation | Graph send is present, but no Outlook server-side draft creation or reply-draft API boundary is exposed for `draftReply`. Local draft persistence can store provider `outlook`, but product wiring is not present. | `Packages/Mail/MailProviders/Sources/MailProviders/Graph/GraphAPI.swift`, `Packages/Core/Persistence/Sources/Persistence/SendQueuePersistence.swift` |

## Product Support Classification

- Read/sync: implemented as provider code and tests, but not product-supported because Outlook account connection and runtime sync routing remain disabled.
- Draft creation: no usable Outlook provider boundary for Trust MVP `draftReply`.
- Message mutation: low-level Graph mutation methods exist, but no safe product action path exists because action outbox routing, idempotent execution, UI enablement, and post-mutation local reconciliation are missing.
- Send/reply: low-level Graph send executor exists, but compose runtime is Gmail-only.

## Missing Before Outlook Mutations

- Provider-neutral account connection that can authorize Outlook, fetch a verified mailbox/profile identity, store credentials under the Outlook token scope, and run real-account smoke tests.
- Provider-neutral sync orchestration that routes Outlook accounts to `GraphMailSyncEngine` without weakening Gmail `History API` behavior.
- A Graph action executor behind `ActionExecuting` with privacy-safe metadata, idempotent completed `op_id` suppression through the existing outbox execution store, and retryable/non-retryable failure mapping.
- Explicit mapping from Trust MVP action kinds to Outlook semantics:
  - `draftReply`: decide whether this creates a local draft only or a Graph reply draft.
  - `archiveThread`: verify archive folder availability and fallback behavior for accounts without a provider archive convention.
  - `starThread`: map to Graph flag without leaking Gmail starred semantics.
  - `markRead`: patch `isRead`.
  - `trashThread`: move to Deleted Items.
- Local reconciliation after Graph mutations. The app must either update local records through a provider-neutral mutation reconciliation path or force a per-folder delta refresh without corrupting opaque Graph delta checkpoints.
- Outlook attachment byte-provider wiring remains separate and should not be bundled with action mutation enablement unless the release gate explicitly expands scope.

## Next Implementation Step

Create a dedicated Outlook action implementation plan that starts with architecture, not code:

1. Update or add an ADR for Outlook action mutations and reconciliation.
2. Introduce provider-neutral runtime routing for account connection, sync, send, and actions.
3. Add `GraphActionExecutor` behind `ActionExecuting`, but keep UI entry points disabled for Outlook until real-account smoke tests pass.
4. Add package tests for Graph action success, duplicate suppression through `action_outbox`, expired auth, insufficient scope, rate limiting, provider rejection, and local reconciliation.
5. Run the manual Outlook smoke criteria before product enablement.

## ADR Requirement

ADR required before enabling Outlook action mutations: yes.

Reason: enabling Outlook action execution affects provider mutation contracts, account runtime routing, sync checkpoint recovery, local reconciliation, and user-visible semantics for archive, flag/star, trash, and draft reply. ADR 0005 defines the Graph provider baseline and scopes, but it does not decide the action outbox to Graph mutation contract or rollback behavior for Outlook action execution.

No ADR was required for this documentation-only spike because it added no scopes, schema, provider calls, mutation behavior, or product entry points.

## Rollback

No runtime rollback is required for this task. The change is documentation-only. If later Outlook action implementation is reverted, keep Outlook account rows, folder rows, and `graph_delta_checkpoint` rows dormant; disable Outlook UI and executor routing while Gmail remains active.
