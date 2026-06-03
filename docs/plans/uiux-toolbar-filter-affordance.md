# Plan: UIUX Toolbar Filter Affordance

## Summary
Fix the toolbar Filter icon so it is not a no-op. Chosen approach: make it open a compact filter popover that controls the existing inbox filter state without duplicating filter logic. If that creates excessive coupling, remove the icon and rely on the visible filter chip row. Non-goal: adding new search syntax or server-side filters.

## Impact Checklist
- Business flow: Filtering inbox threads becomes discoverable from the toolbar and remains consistent with the filter row.
- Domain boundaries: MainScene coordinates filter state; InboxFeature remains the source of filter semantics.
- API / contracts: May add a small toolbar filter option view model in Apps/MacApp. Avoid importing app-only UI into DesignSystem.
- Schema / data model: None.
- Auth / permissions: None.
- Cache / queue / async workflow: None.
- Observability: None.
- Migration: None.
- Rollback: Revert toolbar and popover changes, or remove the icon.
- Debt impact: Retires a broken affordance and avoids hidden duplicate filter state.
- ADR required: no.

## Validation Commands
- `git diff --check`
- `swiftlint --strict --reporter xcode`
- `swift test --package-path Packages/Features/InboxFeature`
- `swift test --package-path Packages/Core/DesignSystem`
- `xcodebuild build -project PrivateAIMail.xcodeproj -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 1: Trace existing filter state ownership
- [x] Inspect `Apps/MacApp/Sources/Views/RBToolbar.swift`, `Apps/MacApp/Sources/Scenes/MainScene.swift`, `Packages/Features/InboxFeature/Sources/InboxFeature/InboxView.swift`, and the `ThreadFilter` definition.
- [x] Confirm whether toolbar can safely receive filter state through generic inputs without importing InboxFeature-specific UI into DesignSystem.
- [x] Choose either popover implementation or icon removal; prefer the popover if it stays low-coupling and testable.

Decision: implement a compact app-layer toolbar popover. `InboxStore.filter` and `ThreadFilter` remain owned by `InboxFeature`; `InboxView` keeps the visible chip row as the canonical in-pane filter indicator. `MainScene` should bridge `ThreadFilter.allCases`, the current `inboxStore.filter`, and a setter into `RBToolbar`. `RBToolbar` can stay decoupled by accepting generic option values such as id, label, selected state, and selection callback, without importing `InboxFeature` or moving filter semantics into `DesignSystem`.

### Task 2: Implement the working affordance
- [ ] Replace the empty Filter action in `RBToolbar` with a real handler and accessibility label/help text.
- [ ] If using a popover, expose current filter and choices from MainScene and update `inboxStore.filter` from the toolbar popover.
- [ ] Keep the visible filter chip row as the canonical in-pane filter indicator; the toolbar popover must mirror the same state, not create another filter model.
- [ ] If removing the icon, remove all dead callback plumbing and leave search/filter discovery intact in `InboxView`.

### Task 3: Test filter behavior
- [ ] Add or update InboxFeature tests proving filter changes still affect filtered threads.
- [ ] Add a light App-level test if existing test infrastructure supports constructing toolbar filter state without launching the app.
- [ ] Run `swift test --package-path Packages/Features/InboxFeature` and fix failures.
- [ ] Run `swift test --package-path Packages/Core/DesignSystem` if any shared atoms changed.

### Task 4: Validate final integration
- [ ] Run `swiftlint --strict --reporter xcode`.
- [ ] Run `git diff --check`.
- [ ] Run the MacApp Debug build and fix failures.

## Rollback / Recovery
- Revert toolbar/MainScene/InboxFeature changes. No data migration is involved.

## Notes
- Project `CLAUDE.md` context is required; launch ralphex with `--codex --pass-claude-md`.
