# Plan: UIUX Trust Action Sheet Scope

## Summary
Reduce action sheet overpromising by making only currently executable Trust MVP actions look actionable. Future integrations may be visible as roadmap/context, but must not use operational preview copy or primary action affordances. Non-goal: adding CRM/task/share/snooze integrations.

## Impact Checklist
- Business flow: Supervised action discovery becomes more honest and reduces failed expectation.
- Domain boundaries: ActionsFeature owns action sheet presentation; IntegrationDomain action contracts should remain unchanged.
- API / contracts: Prefer no public contract changes. If a view model is added, keep it inside ActionsFeature unless tests need public access.
- Schema / data model: None.
- Auth / permissions: None.
- Cache / queue / async workflow: None; no new action execution paths.
- Observability: None, unless existing action request logging is touched.
- Migration: None.
- Rollback: Revert ActionSheetView and tests.
- Debt impact: Retires misleading disabled operational UI; may leave a clearly labeled roadmap section.
- ADR required: no, if action contracts stay unchanged.

## Validation Commands
- `git diff --check`
- `swiftlint --strict --reporter xcode`
- `swift test --package-path Packages/Features/ActionsFeature`
- `xcodebuild build -project PrivateAIMail.xcodeproj -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 1: Separate executable actions from future actions
- [ ] Inspect `Packages/Features/ActionsFeature/Sources/ActionsFeature/ActionSheetView.swift` and `Packages/Features/ActionsFeature/Sources/ActionsFeature/TrustActionUIStore.swift`.
- [ ] Keep executable actions aligned with `TrustMVPAction` and current implementation: draft reply, archive, star, mark read, trash if appropriate for this surface.
- [ ] Move non-executable actions (`snooze`, `log`, `task`, `unsub`, `rule`, `share`) out of the primary action grid or label them as unavailable roadmap items without `Do it` preview.

### Task 2: Rewrite preview and CTA behavior
- [ ] Ensure the preview text describes only actions that can run in this build.
- [ ] Remove "Re:Box will" preview copy for disabled future integrations.
- [ ] Keep the primary CTA disabled only when no executable action is selected; avoid a default selected future action.
- [ ] Make unavailable items visually secondary and non-confusable with enabled tiles.

### Task 3: Add tests for trust scope
- [ ] Add or update ActionsFeature tests to prove disabled/future actions cannot become selected executable actions.
- [ ] Add a test that all enabled action sheet items map to current Trust MVP actions or a documented fallback.
- [ ] Run `swift test --package-path Packages/Features/ActionsFeature` and fix failures.

### Task 4: Validate app integration
- [ ] Verify `MainScene.handleActionSheet` no longer has UI paths that show "Action not available yet" for actions that looked executable.
- [ ] Run `swiftlint --strict --reporter xcode`.
- [ ] Run `git diff --check`.
- [ ] Run the MacApp Debug build and fix failures.

## Rollback / Recovery
- Revert ActionsFeature and MainScene action-sheet changes. No migration or persisted state is involved.

## Notes
- Project `CLAUDE.md` context is required; launch ralphex with `--codex --pass-claude-md`.
