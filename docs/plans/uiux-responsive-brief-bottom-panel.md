# Plan: UIUX Responsive Brief Bottom Panel

## Summary
Make the side/bottom brief and bottom work panel adapt to window size so reading space is not crushed. The implementation should preserve the existing user preference for side vs bottom placement while adding safer constraints and automatic behavior only when the current window cannot support the chosen layout. Non-goal: replacing the AppKit split controller or redesigning the full mail workspace.

## Impact Checklist
- Business flow: Reading long email threads and drafting replies remains usable across smaller macOS windows.
- Domain boundaries: MainScene and ThreadFeature own layout orchestration; DesignSystem owns shared dimensions.
- API / contracts: May add layout policy helpers or bindings, but avoid public package API churn unless tests need it.
- Schema / data model: No schema change. Existing AppStorage keys may be reused; add new keys only if necessary.
- Auth / permissions: None.
- Cache / queue / async workflow: None.
- Observability: None.
- Migration: If a new AppStorage key is added, provide safe default behavior.
- Rollback: Revert layout policy and AppStorage additions.
- Debt impact: Retires fixed-height/fixed-width pressure; may add one explicit layout policy abstraction.
- ADR required: no, if no persistent layout contract beyond AppStorage defaults changes. If adding a durable layout policy abstraction shared across packages, add a short ADR note.

## Validation Commands
- `git diff --check`
- `swiftlint --strict --reporter xcode`
- `swift test --package-path Packages/Features/ThreadFeature`
- `swift test --package-path Packages/Core/DesignSystem`
- `xcodebuild build -project PrivateAIMail.xcodeproj -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 1: Define responsive layout policy
- [x] Inspect `Apps/MacApp/Sources/Views/MainSplitController.swift`, `Apps/MacApp/Sources/Scenes/MainScene.swift`, `Apps/MacApp/Sources/Scenes/MainSceneBriefPanel.swift`, `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift`, and `ThreadView+BottomPanel.swift`.
- [x] Define minimum comfortable reading width and bottom panel height behavior using `RBLayout` constants where possible.
- [x] Keep user preference (`pam.layout.briefPlacement`, collapsed states, stored widths) intact unless the current window cannot satisfy constraints.

### Task 2: Make bottom panel height safer
- [x] Replace the fixed `318` expanded bottom panel height with a constrained responsive height that respects the available window height.
- [x] Ensure collapsed height remains stable and does not hide tab controls.
- [x] Prevent the bottom panel from covering or shrinking the message scroll area below a usable minimum.
- [x] Preserve animations without animating expensive or layout-jarring properties beyond SwiftUI/AppKit norms.

### Task 3: Improve side brief collapse behavior
- [ ] Adjust `MainSplitController` constraints or MainScene policy so side brief can auto-collapse or prefer bottom layout when total width is too small.
- [ ] Preserve stored side width and restore it when returning to a wide window.
- [ ] Ensure `briefCollapsed` and `briefPlacementRaw` do not fight each other when switching between bottom and side placement.

### Task 4: Add tests and validate
- [ ] Add tests for layout policy helpers if extracted.
- [ ] Add ThreadFeature tests/previews for bottom panel collapsed, expanded, draft tab, and brief tab states.
- [ ] Run `swift test --package-path Packages/Features/ThreadFeature` and fix failures.
- [ ] Run `swift test --package-path Packages/Core/DesignSystem`, `swiftlint --strict --reporter xcode`, `git diff --check`, and the MacApp Debug build; fix failures.

## Rollback / Recovery
- Revert layout policy, ThreadView bottom panel, and MainSplitController changes. Existing AppStorage layout values remain compatible.

## Notes
- Project `CLAUDE.md` context is required; launch ralphex with `--codex --pass-claude-md`.
