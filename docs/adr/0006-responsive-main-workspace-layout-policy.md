# ADR 0006: Responsive Main Workspace Layout Policy

Date: 2026-06-03

Status: Accepted

## Context

The main macOS workspace combines sidebar, thread list, reading pane, AI brief
rail, and the bottom Draft/Brief work panel. Fixed pane widths and a fixed
expanded bottom panel height could crush the message reading area on narrower or
shorter windows.

The UI needs responsive behavior without rewriting user preference stored in
AppStorage. Side-vs-bottom brief placement, side rail collapse state, and stored
pane widths are user preferences; temporary narrow-window placement is a
presentation decision.

## Decision

- `DesignSystem` owns shared workspace layout dimensions in `RBLayout`.
- `DesignSystem` owns shared responsive policy in `RBResponsiveLayoutPolicy` for
  side-brief fit checks and bottom-panel height calculation.
- `RBBriefPanelPlacement` is the shared side/bottom placement vocabulary used by
  MacApp scene orchestration.
- `MainScene` owns persisted AppStorage preferences and computes effective brief
  placement transiently from available window width.
- `ThreadFeature` consumes the shared bottom-panel height policy and must not
  hard-code competing bottom-panel height literals.
- When a visible side brief is forced into bottom placement by width, the bottom
  panel reveals the Brief tab for that transition without changing the stored
  side/bottom placement preference.

## Consequences

- Layout math stays in one package instead of being duplicated between MacApp and
  ThreadFeature.
- User placement and pane-width preferences survive narrow-window presentation
  changes and are restored when wider layouts return.
- The shared policy is now an explicit cross-package contract; future changes to
  workspace fit thresholds should update policy tests and this ADR if the
  boundary changes.

## Rollback

Revert the `RBResponsiveLayoutPolicy` additions and the MacApp/ThreadFeature
consumers. Existing AppStorage values remain compatible because no storage keys
or value formats changed.
