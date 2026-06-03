# Plan: UIUX Accessible Hit Targets

## Summary
Increase small interactive target stability across toolbar icons, filter chips, sidebar rows, thread header actions, and bottom panel controls without changing the Re:Box visual language. The UI should remain dense and desktop-native, but repeated controls need predictable minimum sizes and focus/hover affordances.

## Impact Checklist
- Business flow: Frequent navigation and actions become easier to hit and more accessible.
- Domain boundaries: DesignSystem owns atom sizes; feature views consume those atoms or add local min-height constraints.
- API / contracts: May change DesignSystem component sizing but should avoid breaking call sites.
- Schema / data model: None.
- Auth / permissions: None.
- Cache / queue / async workflow: None.
- Observability: None.
- Migration: None.
- Rollback: Revert DesignSystem sizing changes and local min-height changes.
- Debt impact: Retires inconsistent small targets; may add shared size tokens.
- ADR required: no.

## Validation Commands
- `git diff --check`
- `swiftlint --strict --reporter xcode`
- `swift test --package-path Packages/Core/DesignSystem`
- `swift test --package-path Packages/Features/InboxFeature`
- `swift test --package-path Packages/Features/ThreadFeature`
- `xcodebuild build -project PrivateAIMail.xcodeproj -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 1: Audit target sizes in code
- [x] Inspect `Packages/Core/DesignSystem/Sources/DesignSystem/Components/RBIconButton.swift`, `RBFilterChip.swift`, `RBButtonStyle.swift`, and `RBToneSegment.swift`.
- [x] Inspect local controls in `Apps/MacApp/Sources/Views/RBSidebar.swift`, `Apps/MacApp/Sources/Views/RBToolbar.swift`, `ThreadView+HeaderActions.swift`, `ThreadView+BottomPanel.swift`, and `InlineComposer.swift`.
- [x] Identify controls below a stable desktop target size, especially 28x28 icon buttons and chips with 4px vertical padding.

Task 1 audit findings:
- `RBIconButton` is the primary shared issue: it is documented as 28x28 and frames its image container to 28x28, so every toolbar icon button using it inherits an undersized target.
- `RBFilterChip` and `RBToneSegment` both use 12px text with 4px vertical padding and no explicit minimum height, leaving chip and segment targets content-driven.
- `RBPrimaryButtonStyle`, `RBSecondaryButtonStyle`, and `RBGhostButtonStyle` use shared padding but no minimum height or focus treatment, so text buttons and compact icon-only buttons depend on label size and caller controlSize.
- `RBToolbar` uses `RBIconButton` for sidebar, filter, theme, Brief, settings, and compose actions. Its `AccountSwitcher` uses 5px vertical padding and no minimum height.
- `RBSidebar` section headers and folder/account rows use plain buttons with content shapes and 6px vertical row padding, but no stable minimum row height.
- `ThreadView+HeaderActions` compact action buttons constrain only the icon to 18x18 and rely on the shared ghost button padding for the actual hit area; they already provide help text via the title.
- `ThreadView+BottomPanel` collapse uses a 22x22 icon frame with `rbGhost`, and panel tabs use 5px vertical padding with no minimum height.
- `InlineComposer` has a language chevron as a plain icon-only button without an explicit target size, language-picker rows with 6px vertical padding, status-strip buttons forced to `.controlSize(.small)`, and a narrow icon-only edit button that relies on shared secondary button sizing.

### Task 2: Update shared atom sizing
- [x] Increase `RBIconButton` to a stable target size, preferably 32x32 or 36x36, while preserving visual density.
- [x] Add minimum height to `RBFilterChip` and shared button styles if needed.
- [x] Ensure hover, disabled, and focus/keyboard states remain visible after resizing.
- [x] Update DesignSystem previews/tests as needed.

### Task 3: Update feature-level rows and compact controls
- [x] Add stable min heights or content shapes for sidebar section headers and rows.
- [x] Review thread header compact action buttons so icon-only fallbacks still have accessible labels/help and stable target size.
- [x] Review bottom panel collapse and tab controls for stable click targets.
- [x] Fix any text wrapping introduced by larger targets.

### Task 4: Validate accessibility-adjacent behavior
- [x] Run `swift test --package-path Packages/Core/DesignSystem` and fix failures.
- [x] Run relevant InboxFeature and ThreadFeature tests.
- [x] Run `swiftlint --strict --reporter xcode`.
- [x] Run `git diff --check` and the MacApp Debug build; fix failures.

Code review follow-up:
- Fixed audited targets that were still unresolved after the first pass:
  `AccountSwitcher`, the InlineComposer language chevron, and InlineComposer
  language picker rows now use the shared compact hit target.
- Simplified the shared sizing contract to `RBControlMetrics.compactHitTarget`
  instead of public aliases that all pointed at the same value.
- Kept compact thread header actions at a final 32 pt target by using
  `RBIconButton` instead of stacking the compact frame inside `.rbGhost`
  padding.
- Increased the collapsed bottom panel height to contain the 32 pt chrome plus
  vertical padding.

Second review follow-up:
- Added explicit disabled visual states for shared text buttons and the
  compact chip, segment, and account-switcher atoms.
- Kept `RBIconButton` internals on the stable path after verifying that
  SwiftUI disabled/focus modifiers inside the atom crashed feature
  `NSHostingView` snapshot tests with signal 11; disabled compact thread
  actions now render a noninteractive 32 pt disabled icon instead.

## Rollback / Recovery
- Revert DesignSystem atom sizing and local row/control adjustments. No migration is involved.

## Notes
- Project `CLAUDE.md` context is required; launch ralphex with `--codex --pass-claude-md`.
