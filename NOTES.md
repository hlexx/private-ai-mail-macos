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

### Brief rail

Brief rail stubs removed in step 4. `BriefStore` now calls
`AIService.threadBrief()` for all thread IDs via the on-device MLX backend.

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

## Sparkle EdDSA key management

### Where the keys live

- **Private key**: macOS login Keychain (account: `ed25519`, service:
  `https://sparkle-project.org`). Never exported to a file, never committed.
- **Public key**: `Apps/MacApp/Info.plist` under `SUPublicEDKey`.

### Key rotation

1. Run `./tools/sparkle/generate_keys` — this overwrites the Keychain entry
   and prints a new public key.
2. Update `SUPublicEDKey` in `Apps/MacApp/Info.plist` with the new value.
3. Ship a **transitional release** signed with the **old** key that contains
   the **new** public key in its Info.plist. Users who installed via the old
   key will auto-update to this transitional build. After that, all
   subsequent releases are signed with the new key and verified against the
   new public key already baked into the installed app.
4. If the old key is lost (no transitional release possible), users must
   manually re-download the app — there is no recovery path for EdDSA key
   loss.

### Sparkle tools

`tools/sparkle/generate_keys` and `tools/sparkle/sign_update` are extracted
from the Sparkle 2.9.1 release. They are checked in as small native binaries
(~200 KB each). `sign_update` reads the private key from Keychain to produce
an EdDSA signature for a DMG file.

## Code signing & notarization

### Environment variables

Three env vars control code signing and notarization. All are optional — if
none are set, the build falls back to ad-hoc signing.

| Variable | Purpose | Where to get it |
|---|---|---|
| `RELEASE_DEVELOPER_TEAM` | Apple Developer Team ID (e.g. `ABCDE12345`) | Apple Developer portal → Membership → Team ID |
| `RELEASE_APPLE_ID` | Apple ID email used with `notarytool` | Your Apple Developer account email |
| `RELEASE_APPLE_PW` | App-specific password for `notarytool` | [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords → Generate |

### Getting an app-specific password

1. Go to [appleid.apple.com](https://appleid.apple.com) and sign in.
2. Navigate to **Sign-In and Security** → **App-Specific Passwords**.
3. Click **Generate an app-specific password**, name it (e.g. "notarytool").
4. Copy the generated password and use it as `RELEASE_APPLE_PW`.

### Finding your Team ID

1. Go to [developer.apple.com/account](https://developer.apple.com/account).
2. Scroll to **Membership details**.
3. Copy the **Team ID** (10-character alphanumeric string).

### Signing tiers

- **Tier A (ad-hoc, default)**: No env vars needed. Testers must right-click →
  Open on first launch. Sparkle EdDSA verification still works.
- **Tier B (Developer ID + notarization)**: Set all three env vars. The app
  passes Gatekeeper without the right-click dance.

### Scripts

- `scripts/sign-app.sh <app-path>` — codesigns the `.app` bundle.
- `scripts/notarize-dmg.sh <dmg-path>` — submits DMG to Apple notarization,
  staples the ticket, and verifies Gatekeeper assessment. Exits cleanly if
  env vars are missing.

## CI release workflow

### Overview

`.github/workflows/release.yml` runs on any pushed tag matching `v*`. It builds
a Release-configuration DMG and creates a **draft** GitHub Release with the DMG
and SHA-256 checksum attached. The maintainer publishes manually after smoke.

### CI secrets and variables

| Name | Type | Required? | Purpose |
|---|---|---|---|
| `GITHUB_TOKEN` | Secret (auto) | Yes | Provided automatically by GitHub Actions |
| `RELEASE_APPLE_ID` | Secret | No (Tier B only) | Apple ID for `notarytool` |
| `RELEASE_APPLE_PW` | Secret | No (Tier B only) | App-specific password for `notarytool` |
| `RELEASE_DEVELOPER_TEAM` | Variable | No (Tier B only) | Apple Developer Team ID for codesigning |

Without the optional secrets, the workflow produces an ad-hoc-signed DMG (Tier A).

### Sparkle private key on CI

The Sparkle EdDSA private key is **NOT** stored on CI. It lives exclusively in
the maintainer's macOS login Keychain (see "Sparkle EdDSA key management" above).

The release workflow builds the DMG and creates a draft release, but does **not**
generate `appcast.xml` — that requires the private key for EdDSA signing.

**Workflow for cutting a release:**

1. Push a version tag: `git tag v0.1.0-alpha && git push origin v0.1.0-alpha`
2. CI builds the DMG, creates a draft release with the DMG attached.
3. On the maintainer's machine (where the Keychain has the key):
   - Download the DMG from the draft release (or build locally via `make release`)
   - Run `make appcast` to generate the signed `appcast.xml`
   - Upload: `gh release upload v0.1.0-alpha dist/appcast.xml --clobber`
4. Smoke-test, then publish the release.

If a future contributor wants fully automated CI releases, they would need to
store the EdDSA private key as an encrypted CI secret and modify `sign_update` to
read from a file instead of Keychain. This changes the threat model — document
and assess before proceeding.

## On-device AI runtime

Thread briefs are generated on-device via **MLX** running **Gemma 4 E2B IT, 4-bit
quantised** (`mlx-community/gemma-4-e2b-it-4bit`, 1.21B params). Zero network
traffic at inference time. The model is loaded for real via `MLXLLM`
(`mlx-swift-lm`) — not a stub.

### Model selection

Three models were evaluated during step 4.5:
- `gemma-4-e4b-it-OptiQ-4bit` (7.5B) — rejected, mlx-swift-lm can't load OptiQ mixed-precision weights
- `gemma-4-e4b-it-4bit` (7.5B) — rejected, p95 latency 48s (budget: <=15s)
- `gemma-4-e2b-it-4bit` (1.21B) — selected, p50=3.57s, p95=6.17s, 100% schema validity

Full comparison: `docs/eval-reports/step4.5-model-selection.md`

### Model location

`~/Library/Application Support/PrivateAIMail/models/gemma-4-e2b-it-4bit/`

The model is downloaded automatically on first launch (~3.6 GB). A blocking
"Setting up local AI" screen shows progress. The download is resumable — killing
the app mid-download and relaunching continues from where it left off.

### Model spec source

`Packages/AI/AIRuntime/Sources/AIRuntime/GemmaModelSpec.swift` defines the
HuggingFace mirror URL, file manifest, and expected SHA-256 digests. The model
tracks `mlx-community/gemma-4-e2b-it-4bit` at a pinned revision. Key files
(model weights, tokenizer) are verified by SHA-256 digest after download.

### Wiping and re-downloading

Delete the model directory and relaunch the app:
```bash
rm -rf ~/Library/Application\ Support/PrivateAIMail/models/
# Relaunch → setup screen appears → model re-downloads
```

### MLX dependency

`Packages/AI/AIRuntime/Package.swift` and `Packages/AI/AIEmbeddings/Package.swift`
depend on [`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift)
(>= 0.21.0). `AIRuntime` also depends on
[`ml-explore/mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm) for
the `MLXLLM` and `MLXLMCommon` modules (model loading, tokenization, generation).
MLX ships Metal shader source that requires the **Metal Toolchain** component —
CI downloads it automatically (`sudo xcodebuild -downloadComponent MetalToolchain`).

Local development: if you see Metal compiler errors, run
`sudo xcodebuild -downloadComponent MetalToolchain` once.

### Eval reports

Baseline eval report: `docs/eval-reports/step4-baseline.md`. Generated by the
`AIEvals` package CLI runner (`swift run EvalRunnerCLI`). Measures faithfulness,
hallucination rate, schema validity, and latency over a 20-thread synthetic corpus.

Real numbers (step 4.5, gemma-4-e2b-it-4bit): p50=3.57s, p95=6.17s,
schema validity 100%, faithfulness 1.000, hallucination 0.0%.

Prompt tuning notes: `docs/eval-reports/step4-prompt-notes.md`.

## Release smoke testing

### Sparkle auto-update end-to-end verification

This procedure verifies the full Sparkle update lifecycle. Run after
cutting a new alpha release.

#### Prerequisites

- v0.1.0-alpha installed in `/Applications/PrivateAIMail.app` (from the DMG)
- The Sparkle EdDSA private key is in the developer's macOS login Keychain
- `appcast.xml` is uploaded as a GitHub Release asset on the `latest` release

#### Step 1: Verify "up to date" state

1. Open PrivateAIMail on the test machine (or separate user account).
2. Menu bar → PrivateAIMail → **Check for Updates…**
3. Expected: Sparkle reports "You're up to date" (the live appcast only
   lists v0.1.0-alpha, which matches the installed version).

#### Step 2: Build a newer version

On the developer machine:

```bash
# 1. Bump version in Project.swift
#    MARKETING_VERSION → "0.1.1-alpha"
#    CURRENT_PROJECT_VERSION → "101"

# 2. Build + package
make release    # builds .app, signs, creates DMG, generates appcast.xml

# 3. Create a draft release on GitHub
gh release create v0.1.1-alpha --draft \
  --title "v0.1.1-alpha" \
  --notes-file release-notes/v0.1.1-alpha.md \
  dist/PrivateAIMail-0.1.1-alpha.dmg \
  dist/PrivateAIMail-0.1.1-alpha.sha256

# 4. Update the appcast.xml on the LATEST release so SUFeedURL resolves it
gh release upload v0.1.0-alpha dist/appcast.xml --clobber
```

#### Step 3: Verify update flow

1. On the test machine, open PrivateAIMail.
2. Menu bar → PrivateAIMail → **Check for Updates…**
3. Expected: Sparkle finds v0.1.1-alpha in the appcast, shows the update
   prompt with release notes.
4. Click **Install Update**.
5. Expected: Sparkle downloads the DMG, verifies the EdDSA signature,
   extracts the new `.app`, replaces the installed copy, and relaunches.
6. After relaunch, verify:
   - About dialog shows version 0.1.1-alpha (build 101).
   - Previously connected Gmail accounts are still present (no DB reset).
   - The on-device model is still available (no re-download).
   - Thread list loads and AI briefs generate normally.

#### Step 4: Gatekeeper verification (Tier B only)

If the release was signed with Developer ID and notarized:

```bash
spctl -a -v /Applications/PrivateAIMail.app
# Expected: "accepted" with source "Developer ID"
```

If ad-hoc signed (Tier A), skip this step — Gatekeeper will show the
unsigned-app warning on first launch (right-click → Open to bypass).

#### Smoke result log

Record each smoke test result here:

| Date | Version tested | Update from | Result | Notes |
|------|---------------|-------------|--------|-------|
| (pending) | v0.1.0-alpha | fresh install | (pending) | First alpha, manual smoke after merge |

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
