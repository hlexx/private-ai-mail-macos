# Plan: UIUX Explicit Inline Draft Generation

## Summary
Make AI draft generation in the inline composer explicit instead of automatic on thread selection. The goal is to preserve the privacy-first trust contract: opening a thread may show a brief, but generating a reply draft must be clearly user-triggered. Non-goal: changing provider send contracts, persistence schema, or the local AI prompt format beyond what is required to avoid auto-starting draft generation.

## Impact Checklist
- Business flow: Thread reading and reply drafting become more intentional; users keep control before AI creates reply text.
- Domain boundaries: ComposeFeature owns draft generation state; MainScene only decides when the composer is visible.
- API / contracts: May add a narrow ComposeFeature view/API flag or method for explicit initial generation. Do not change provider APIs.
- Schema / data model: None.
- Auth / permissions: None.
- Cache / queue / async workflow: Changes when `ReplyStore.generate` runs; keep cancellation/cache behavior intact.
- Observability: Preserve privacy-safe `ai.draft_reply` generated/failed logs only when generation actually starts.
- Migration: None.
- Rollback: Revert the ComposeFeature/MainScene changes and ADR/doc note.
- Debt impact: Retires hidden AI work on selection; may introduce one small explicit-generation state if needed.
- ADR required: yes. Update the existing AI/action ADR if it already covers draft initiation policy; otherwise add a short ADR documenting user-triggered draft generation.

## Validation Commands
- `git diff --check`
- `swiftlint --strict --reporter xcode`
- `swift test --package-path Packages/Features/ComposeFeature`
- `swift test --package-path Packages/Features/ThreadFeature`
- `xcodebuild build -project PrivateAIMail.xcodeproj -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 1: Map current draft initiation paths
- [x] Inspect `Apps/MacApp/Sources/Scenes/MainScene.swift`, `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift`, `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView+BottomPanel.swift`, `Packages/Features/ComposeFeature/Sources/ComposeFeature/InlineComposer.swift`, and `Packages/Features/ComposeFeature/Sources/ComposeFeature/ReplyStore.swift`.
- [x] Identify every user action that should create/focus/regenerate a draft: brief CTA, thread Draft action, bottom panel Draft tab, regenerate, edit in full, and send.
- [x] Record the intended behavior in code comments or tests only where it affects an ambiguous boundary.

### Task 2: Stop automatic draft generation on thread open
- [x] Change `InlineComposer` so `.task(id:)` does not call `replyStore.generate` merely because the view appears.
- [x] Add an explicit empty/ready state in the inline composer that explains local draft generation without starting it.
- [x] Keep cached draft display/focus behavior when a user already generated a draft for the same thread/tone/language.
- [x] Ensure changing tone or reply language regenerates only after a draft has already been requested, or exposes an explicit generate action before the first request.

### Task 3: Wire explicit user actions to generation
- [x] Wire `BriefRail` draft CTA and thread `Draft` action to call an explicit generate/focus path such as `ReplyStore.generateIfNeeded`.
- [x] Ensure opening the bottom Draft panel does not generate unless it was opened through a draft action or the user presses Generate.
- [x] Preserve `Edit in full`, Send, Retry, Re-authorize, and Regenerate behavior after an explicit draft exists.
- [x] Add or update ComposeFeature and ThreadFeature tests for no auto-generation on view appear and generation on explicit action.

### Task 4: Document the policy and validate
- [ ] Update the relevant ADR or create a new ADR for the explicit draft-generation trust contract.
- [ ] Run `swift test --package-path Packages/Features/ComposeFeature` and fix failures.
- [ ] Run `swift test --package-path Packages/Features/ThreadFeature` and fix failures.
- [ ] Run `swiftlint --strict --reporter xcode`, `git diff --check`, and the MacApp Debug build; fix failures.

## Rollback / Recovery
- Revert the ComposeFeature/ThreadFeature/MainScene changes and the ADR/doc update. No data migration is involved.

## Notes
- Project `CLAUDE.md` context is required; launch ralphex with `--codex --pass-claude-md`.
