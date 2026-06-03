# Plan: UIUX Settings Surface Polish

## Summary
Bring Settings closer to the Re:Box design quality without sacrificing native macOS form accessibility. Increase the settings window scale, improve information density for long privacy copy, and give General/Privacy/Accounts/AI tabs a more consistent surface treatment. Non-goal: changing account auth flows, privacy promises, or provider permissions.

## Impact Checklist
- Business flow: Users can understand privacy, language, AI, keyboard, and account settings with less cramped copy.
- Domain boundaries: SettingsFeature owns tab content; MacApp SettingsScene owns window sizing.
- API / contracts: None expected. If reusable settings rows are added, keep them in SettingsFeature.
- Schema / data model: None.
- Auth / permissions: None. Do not change provider scopes or reauthorization behavior.
- Cache / queue / async workflow: None.
- Observability: None.
- Migration: Existing AppStorage keys remain unchanged.
- Rollback: Revert SettingsScene layout constants and SettingsFeature view changes.
- Debt impact: Retires cramped system-form appearance and makes privacy copy easier to scan.
- ADR required: no, unless privacy copy semantics or provider permission claims change.

## Validation Commands
- `git diff --check`
- `swiftlint --strict --reporter xcode`
- `swift test --package-path Packages/Features/SettingsFeature`
- `swift test --package-path Packages/Core/DesignSystem`
- `xcodebuild build -project PrivateAIMail.xcodeproj -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 1: Inventory Settings surfaces and copy density
- [ ] Inspect `Apps/MacApp/Sources/Scenes/SettingsScene.swift`, `Packages/Features/SettingsFeature/Sources/SettingsFeature/GeneralTab.swift`, `PrivacyTab.swift`, `AccountsTab.swift`, and `AITab`.
- [ ] Identify rows where long privacy copy wraps awkwardly or competes with accessory controls.
- [ ] Keep native form semantics where they improve keyboard navigation and accessibility.

### Task 2: Resize and structure the Settings window
- [ ] Increase `RBLayout.settingsWidth` and `RBLayout.settingsHeight` to fit current tabs without cramped vertical scrolling.
- [ ] Add a consistent tab content container or section treatment using DesignSystem colors/tokens where it does not break native form behavior.
- [ ] Ensure the Privacy tab supports long text with readable line length and clear accessory alignment.

### Task 3: Improve General and Privacy tab scanability
- [ ] Group translation language controls so they do not appear as an undifferentiated long toggle list.
- [ ] Preserve all existing AppStorage bindings and tests for language preferences.
- [ ] Rework Privacy rows to show status/accessory controls without crowding the explanatory copy.
- [ ] Do not change privacy claims unless backed by docs/tests.

### Task 4: Test and validate Settings
- [ ] Update SettingsFeature tests for any changed state models or copy keys.
- [ ] Run `swift test --package-path Packages/Features/SettingsFeature` and fix failures.
- [ ] Run `swift test --package-path Packages/Core/DesignSystem` if shared components changed.
- [ ] Run `swiftlint --strict --reporter xcode`, `git diff --check`, and the MacApp Debug build; fix failures.

## Rollback / Recovery
- Revert SettingsScene, SettingsFeature, and DesignSystem changes. Existing settings values remain compatible.

## Notes
- Project `CLAUDE.md` context is required; launch ralphex with `--codex --pass-claude-md`.
