# Project notes

## Re:Box UI iteration

This iteration implements the pixel-perfect Re:Box design handoff in the
existing SwiftUI macOS app, redressing every screen component to match the
Claude Design HTML/CSS/JSX prototype.

### Bundled fonts (OFL-licensed)

Three web font families are bundled in `Apps/MacApp/Resources/Fonts/`:

- **Geist** (400/500/600/700) — primary UI font. SIL Open Font License.
- **Instrument Serif** (regular + italic) — decorative serif for the
  reading-pane empty state and display headings.
- **JetBrains Mono** (400/500/600) — monospace for timestamps, metadata,
  eyebrow labels.

License file: `Apps/MacApp/Resources/Fonts/LICENSES.txt`

### Design source

The design handoff lives at `design/re-box/`. The primary file is
`design/re-box/project/Re:Box macOS.html` which imports JSX components
and CSS stylesheets defining every color, type scale, spacing token,
and component.

### Hardcoded stubs

Brief rail and inline composer use hardcoded stub data for demonstration.
Thread IDs ending in `t1` or `t2` get populated briefs; all other threads
show the empty state. Each stub site is marked with a
`// TODO(§15-step-4): remove stub when AIKit lands` comment.

Covered thread IDs (exact match):
- `t1` — "Client approved pricing…" brief (confidence 88%)
- `t2` — "Jonas wants seat count…" brief (confidence 92%)

### Key architectural decisions

- Design tokens live in `Packages/Core/DesignSystem/` — all color, type,
  spacing, radii, and motion tokens. Feature packages consume these and
  do not define their own.
- Theme switching uses `@AppStorage("rb-theme")` cycling system → dark →
  light. The `rbTheme()` modifier applies the preferred color scheme to
  the root view.
- The Compose window uses `NSTextView` via `NSViewRepresentable` for
  rich-text editing, per §14 design decision 4.
- All user-facing strings use `String(localized:defaultValue:)` for
  i18n readiness.

### Post-merge follow-ups

#### Font bundling — fixed

The bundled `.otf` / `.ttf` files end up at `PrivateAIMail.app/Contents/Resources/`
(flat) rather than inside a `Fonts/` subdirectory because Tuist resolves
`resources: ["Apps/MacApp/Resources/**"]` by flattening file references.

The Info.plist `ATSApplicationFontsPath` was originally `Fonts`, so macOS could
not find the files at launch and `Font.custom(...)` silently fell through to
system fonts. The value is now `.` (the Resources root), matching the actual
on-disk layout. This is the **load-bearing one-line fix** for the editorial
typography to render.

If a future refactor moves the fonts into a `Fonts/` subdirectory in the
bundle, update `ATSApplicationFontsPath` to match — or vice versa.

### Design compliance tests

`Packages/Core/DesignSystem/Tests/DesignSystemTests/DesignComplianceTests.swift`
asserts the implementation matches the **Re:Box design source** in
`design/re-box/project/app/`:

- Every `Color.rbGraphite*` / `rbCitron*` / `rbCobalt*` / `rbViolet*` /
  `rbChrome*` / `rbTone*` resolves to the sRGB derived from the OKLCH triple
  in `colors_and_type.css` §2.
- `RBSpace.s1..s20` equal `colors_and_type.css` §6 `--space-*` literals.
- `RBRadius.{xs,sm,md,lg,xl,xl2,pill}` equal §6 `--radius-*` literals.
- `RBDuration.{d1..d4}` equal §6 `--dur-*` literals (ms → seconds).
- `RBTextStyle.fontSize` returns the §5/§7 px scale (`displayXL = 84`,
  `body = 14`, `eyebrow = 11`, …).
- `RBTextStyle.tracking` follows §5 `--tracking-*` ratios.
- `RBLayout` (new) is the single source of truth for window/pane geometry
  and equals `app.css` `.rb-window` / `.rb-panes` / `.rb-read-body`.
- Every `kind` from `data.js` (`due`, `reply`, `att`, `ai`, `logged`, `cc`,
  `cal`, `paid`) maps to a `SignalChip.Kind` case so real thread data
  cannot render without a chip.

If the design moves, edit the constants in
`DesignComplianceTests.swift` first (test goes red), then change the
implementation, then come back here. Don't skip these — they're the
contract with the handoff.

### Known pre-existing follow-up: MacAppTests target build

`Apps/MacApp/Tests/RBSidebarTests.swift` and `RBToolbarTests.swift` use
`@testable import MacApp`, but `MacApp` is a `.app` product (not a
framework), so Swift cannot resolve it as a module — `xcodebuild test`
fails to build the `MacAppTests` target.

Workaround: package tests cover the visual surface (DesignSystem atoms,
per-feature snapshot tests in dark and light). MacAppTests target is
effectively a no-op today.

Proper fix (later): extract `RBSidebar`, `RBToolbar`, `AccountRow`,
`FolderItem` into a new `Packages/Features/AppFrameFeature/` package so
the tests can `@testable import AppFrameFeature` from a package context.

## MLX is linked

`Packages/AI/AIRuntime/Package.swift` and `Packages/AI/AIEmbeddings/Package.swift`
depend on [`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift)
(>= 0.21.0). MLX ships Metal shader source that requires the **Metal Toolchain**
component — CI downloads it automatically
(`sudo xcodebuild -downloadComponent MetalToolchain`).

Local development: if you see Metal compiler errors, run
`sudo xcodebuild -downloadComponent MetalToolchain` once.

Added in Task 1 of `step4-mlx-gemma-thread-brief-plan.md`.

## Tuist file layout

`Tuist/Config.swift` works but generates a deprecation warning. Migrate to
`Tuist.swift` at repo root in a follow-up cleanup.

## What "build green" means

- `tuist generate` succeeds.
- `xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp` succeeds.
- Each `Packages/*/*/` has a green `swift test`.

## Manual smoke test: end-to-end Gmail account flow

1. Delete the sandbox container to start fresh:
   ```bash
   rm -rf ~/Library/Containers/com.hlexx.privateaimail/
   ```
2. Build and run `MacApp` via Xcode (Cmd+R) or:
   ```bash
   tuist generate --no-open
   xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS'
   open DerivedData/PrivateAIMail/Build/Products/Debug/PrivateAIMail.app
   ```
3. Open Settings (Cmd+,) → Accounts tab.
4. Click "Add Gmail account". The system browser opens the Google OAuth
   consent screen.
5. Sign in with a Gmail account and grant the requested scopes
   (`gmail.readonly`, `gmail.metadata`, `userinfo.email`).
6. The Settings tab shows a progress bar while bootstrap sync runs.
7. Within ~60 seconds the sidebar in the main window shows the new
   account, and the thread list populates with the last 30 days of
   Gmail threads sorted by most recent.
8. Select a thread to see its messages in the right pane.
9. Press Cmd+R to trigger incremental sync — new messages should
   appear without restarting the app.
