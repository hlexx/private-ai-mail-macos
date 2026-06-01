# Private AI Mail macOS Agent Notes

## Architecture Boundaries

- Supervised mail actions flow through `ActionCommand`,
  `ActionOutboxExecutionStore`, and an `ActionExecuting` implementation. UI code
  must not call provider mutations directly when the action outbox is available.
- The app runtime currently wires Gmail actions only. Outlook/Graph mutation
  enablement requires a separate ADR-backed plan covering scopes, account
  connection, sync invariants, and rollback.
- `IntegrationDomain` stays provider-neutral. Gmail-specific draft and mailbox
  mutation behavior belongs in `MailProviders` or `MailSync`.
- `TrustActionUIStore` owns approval and recent outbox UI state. Draft reply and
  trash require explicit confirmation; archive, star, and mark-read use the fast
  action path. AI output must not auto-run actions.
- Privacy-safe logs go through `PrivacyObservability`; raw message bodies,
  attachment bytes, prompts, model outputs, provider payloads, bearer tokens,
  refresh tokens, and connector secrets must not be logged.

## Validation Commands

- Default release gate: `PATH=/opt/homebrew/bin:$PATH ./scripts/verify-trust-mvp.sh`
- Full local release gate: `PATH=/opt/homebrew/bin:$PATH FULL_TRUST_MVP_GATE=1 ./scripts/verify-trust-mvp.sh`
- Gate dry run: `VERIFY_TRUST_MVP_DRY_RUN=1 ./scripts/verify-trust-mvp.sh`
- Mac app generation/build gate: `tuist generate --no-open` followed by
  `xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

Use the Homebrew arm64 SwiftLint path first on Apple Silicon. The local machine
has previously exposed an Intel SwiftLint earlier in PATH, which fails before
linting because SourceKitten cannot load the active arm64 sourcekitd.

## Workflow Notes

- Keep plan checkbox updates scoped to the task section actually completed.
- Do not edit the sibling `../EMAIL_ALF` repo from app implementation plans
  unless the task explicitly asks for the product-doc follow-up.
- The SwiftLint baseline is temporary debt for pre-existing size/nesting
  violations. Do not add new entries without either splitting the touched code
  or documenting why the structural fix is deferred.
