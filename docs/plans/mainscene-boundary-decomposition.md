# Plan: MainScene Boundary Decomposition

## Summary
Reduce `MainScene` composition-root pressure without changing user-visible behavior. The current app shell coordinates toolbar search, split layout, brief placement, compose routing, translation, keyboard actions, and trust actions in one large SwiftUI view. The chosen approach is incremental extraction into app-local coordinators/helpers that preserve package boundaries and existing tests. Non-goal: redesigning navigation, replacing the AppKit split controller, or moving provider logic into UI code.

## Impact Checklist
- Business flow: None directly; this is maintainability work that lowers risk for future UI and trust-flow changes.
- Domain boundaries: App target owns orchestration; feature packages keep feature behavior; provider and persistence logic must not leak into `MainScene`.
- API / contracts: Prefer internal app-target helpers. Public package APIs should not change unless existing package ownership already requires it.
- Schema / data model: None.
- Auth / permissions: None.
- Cache / queue / async workflow: None expected. Trust action and compose async flows must remain behaviorally identical.
- Observability: Preserve current privacy-safe logging and do not add raw mail/provider logging.
- Migration: None.
- Rollback: Revert extracted files/helpers. Existing AppStorage keys and persisted layout values remain compatible.
- Debt impact: Retires growing composition-root debt and file-length suppression pressure; may add small app-local types.
- ADR required: no, if extraction stays app-local and behavior-preserving. Add a short ADR only if a new shared coordinator abstraction crosses package boundaries.

## Validation Commands
- `git diff --check`
- `swiftlint --strict --reporter xcode`
- `swift test --package-path Packages/Features/InboxFeature`
- `swift test --package-path Packages/Features/ThreadFeature`
- `swift test --package-path Packages/Features/ComposeFeature`
- `PATH=/opt/homebrew/bin:$PATH ./scripts/verify-trust-mvp.sh`

### Task 1: Inventory current responsibilities and existing split files
- [x] Inspect `Apps/MacApp/Sources/Scenes/MainScene.swift`, `MainSceneMutations.swift`, `MainSceneBriefPanel.swift`, `MainSceneStores.swift`, and `MainSceneTranslation.swift`.
- [x] Identify responsibilities that are pure state/policy and can move without touching feature packages: layout placement, toolbar bindings, keyboard dispatch, action routing, compose focus, translation wiring.
- [x] Preserve existing untracked or in-progress split files; do not collapse or overwrite user work.
- [x] Write down the target file ownership in comments only where ambiguity would cause future boundary leaks.

### Task 2: Extract layout and brief placement policy
- [ ] Move brief placement, collapse, width, and bottom-panel layout policy into an app-local helper or focused extension file.
- [ ] Keep `pam.layout.*` AppStorage keys unchanged.
- [ ] Ensure `MainSplitController` remains responsible only for split-view hosting and constraints, not business decisions.
- [ ] Run focused build/tests after extraction before continuing.

### Task 3: Extract action and compose routing without changing behavior
- [ ] Move `handleAction`, toolbar action handlers, and `handleActionSheet` routing into focused app-local files or helpers.
- [ ] Keep supervised actions routed through `requestTrustActionForSelectedThread` and the outbox path when available.
- [ ] Keep direct provider mutation fallbacks only where they already exist and are explicitly guarded by unsupported trust action state.
- [ ] Verify reply, reply all, forward, archive, star, mark read, trash, and compose send shortcuts behave as before.

### Task 4: Extract translation wiring and reduce view-state churn
- [ ] Keep TranslationFeature logic in its package and move only app-level wiring out of the main view body.
- [ ] Preserve `TranslationLanguagePreferences.storageKey`, preferred language, and auto-translate AppStorage behavior.
- [ ] Ensure translation UI state changes do not trigger unnecessary layout churn or draft regeneration.
- [ ] Run TranslationFeature tests if touched.

### Task 5: Remove avoidable lint suppression and validate
- [ ] Re-run SwiftLint and remove `file_length` suppression from `MainScene.swift` only if the file is now under threshold.
- [ ] Add or update App-level tests only where helpers expose pure behavior worth testing.
- [ ] Run `swiftlint --strict --reporter xcode`, `git diff --check`, and `PATH=/opt/homebrew/bin:$PATH ./scripts/verify-trust-mvp.sh`.
- [ ] If any behavior changes are discovered, revert that extraction slice and keep only behavior-preserving pieces.

## Rollback / Recovery
- Revert app-target extraction commits. No persisted data, schema, provider contract, or auth state is changed.
- If a helper abstraction increases coupling, inline that slice back into the nearest existing extension instead of broadening the abstraction.

## Notes
- Project `CLAUDE.md` context is required; launch ralphex with `--codex --pass-claude-md`.
- Intended branch name: `mainscene-boundary-decomposition`.
