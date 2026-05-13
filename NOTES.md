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

## Why MLX is not yet linked

`Packages/AI/AIRuntime/Package.swift` and `Packages/AI/AIEmbeddings/Package.swift`
intentionally do **not** declare a dependency on
[`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift) in this
skeleton iteration.

Reasons:
1. MLX ships Metal shader source that requires the Xcode 26 **Metal Toolchain**
   component (download via `xcodebuild -downloadComponent MetalToolchain`).
   We don't want CI runners or contributors to pay that cost until we actually
   call MLX.
2. The skeleton's job is to validate the dependency graph and app shell, not
   to compile ML kernels.

When we start the **AI runtime iteration** (step 6 of the §15 roadmap), we
will:
- Add `.package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.20.0")`
  back to the two packages.
- Document the Metal Toolchain install step in the README.
- Update CI to download the Metal Toolchain.

The design decision (MLX primary + llama.cpp escape hatch) is unchanged.
See [§14 of the macOS design doc](../EMAIL_ALF/14_macos_app_design.md#142-чего-не-делаем-сейчас-чтобы-не-тащить-лишнее), decision 3.

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
