# Step 9: Sparkle Appcast + First Alpha Release

## Overview

Cut the first installable alpha of Private AI Mail. After step 9 a
trusted alpha tester can:

1. Download a `.dmg` from a public URL (GitHub Releases)
2. Drag the app to `/Applications`
3. Launch it (right-click → Open once if it's not yet
   Developer-ID-signed)
4. Connect a Gmail account, see the inbox, generate AI briefs, send
   replies — i.e. the full Phase 1 MVP loop from steps 1–7
5. **Get auto-update notifications** when v0.1.1, v0.1.2 etc. land —
   Sparkle 2 picks up the appcast, verifies the EdDSA signature on the
   new build, prompts to install, swaps the app in `/Applications`

This is the final §15 step. Step 8 (push relay) stays deferred to
Phase 2 as agreed.

## Context

- All §15 steps 1–7 are in `main` (commits up to `7b3ba01`). Phase 1
  MVP functionality is complete: OAuth Gmail account, sync, AI brief,
  reply composer, real send.
- `Project.swift` already declares `DEVELOPMENT_TEAM = ""` (empty —
  no Apple Developer ID configured yet). Bundle id is the temporary
  `com.hlexx.privateaimail`.
- `.gitignore` already excludes `*.eddsa_priv` (private key file).
  The Sparkle EdDSA private key never enters the repo; it lives in
  the developer's macOS Keychain (Sparkle's bundled `generate_keys`
  tool stores it there by default).
- `Apps/MacApp/Info.plist` is already wired through Tuist; we add
  Sparkle keys to it directly.
- `Apps/MacApp/PrivateAIMail.entitlements` enables App Sandbox.
  Sparkle 2 in sandboxed apps requires the **Installer XPC service**
  bundled via the SPM package — that's the supported path; we use it.
- macOS 15 / arm64 only, per existing deployment target — Sparkle 2
  supports macOS 10.13+, well within bounds.
- Two paths for distribution are scoped here:
  - **A. Ad-hoc-signed alpha** (default, no Apple Developer Program
    required). Testers do the right-click-Open dance once. Sparkle
    auto-updates still work because they're gated on EdDSA, not on
    Apple's notarization.
  - **B. Developer-ID-signed + notarized** (opt-in, if the user has
    a $99/yr Apple Developer Program account). Triggered by setting
    `RELEASE_DEVELOPER_TEAM` + `RELEASE_APPLE_ID` + `RELEASE_APPLE_PW`
    env vars. Without them the build falls back to A.
- Hosting: **GitHub Releases** for both the `.dmg` and the
  `appcast.xml`. Free, reliable, supports HTTPS, URL is stable per
  asset name. The macOS-repo will publish releases via its existing
  `private-ai-mail-macos` repo on GitHub (assumed already on user's
  account; if it isn't, Task 7 creates the repo and pushes).

## Success Criteria

- `Sparkle` SPM dependency resolved and `MacApp` target links it.
  `SPUStandardUpdaterController` is instantiated in
  `PrivateAIMailApp.swift`. Sparkle's installer XPC service is
  bundled inside the `.app` (verified via `find <app> -name
  Installer.xpc`).
- `Info.plist` carries:
    - `SUFeedURL` → `https://github.com/hlexx/private-ai-mail-macos/releases/latest/download/appcast.xml`
    - `SUPublicEDKey` → base64 EdDSA public key
    - `SUEnableInstallerLauncherService` → `true`
    - `SUEnableDownloaderService` → `true` (for sandboxed apps)
    - `CFBundleShortVersionString` → `0.1.0-alpha`
    - `CFBundleVersion` → `100` (monotonic; integer)
- Two `make` targets work locally:
    - `make release` — builds the app, runs unit tests, packages a
      `.dmg`, signs (Developer ID if env present, else ad-hoc),
      notarizes if signed, stapled if notarized, signs the
      appcast.xml entry with EdDSA, prints the SHA-256 + size
    - `make appcast` — regenerates `appcast.xml` from the latest
      `dist/` artefacts; safe to re-run
- A first GitHub Release `v0.1.0-alpha` exists with two assets:
    - `PrivateAIMail-0.1.0-alpha.dmg`
    - `appcast.xml`
- The DMG passes manual smoke:
    - Mount → drag PrivateAIMail.app to /Applications
    - Launch → first-launch Gmail download proceeds normally
    - App icon appears in /Applications and in Spotlight
- Sparkle update path works end-to-end on a developer machine:
    1. Install v0.1.0-alpha
    2. Bump source to 0.1.1-alpha, `make release`, upload to a
       second draft release; update appcast.xml
    3. Open installed app → Sparkle background check (or
       Check-For-Updates menu item) → prompts to install →
       EdDSA verification passes → app updates → relaunches as 0.1.1
- A `Check for Updates…` menu item is present under the app menu
  group and wired to `SPUStandardUpdaterController.checkForUpdates`.
- README updated with the installation flow (download → drag →
  right-click-Open if unsigned).
- `.gitignore` keeps Sparkle private keys out of the repo (already
  has `*.eddsa_priv`; verify the actual file name and tweak if
  Sparkle's default differs).
- `xcodebuild build` ends with `** BUILD SUCCEEDED **`.
- `swiftlint --strict` reports 0 violations.
- All per-package `swift test` runs exit 0.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && tuist generate --no-open`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && swiftlint --strict`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && make release`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && make appcast`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && find dist/PrivateAIMail.app -name 'Installer.xpc' -maxdepth 6`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' -c 'Print :SUPublicEDKey' dist/PrivateAIMail.app/Contents/Info.plist`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && xmllint --noout dist/appcast.xml`

### Task 1: Add Sparkle SPM dependency + wire installer XPC services

Sparkle 2 ships as a SwiftPM package. For sandboxed apps it requires
**two helper XPC services** (`Installer` and `Downloader`) bundled
inside the `.app`. Both ship with the Sparkle SPM target — we just
have to opt in via Info.plist keys and link the target.

- [x] Add `Apps/MacApp/Project.swift` packages section: `.package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")`. Add `.product(name: "Sparkle", package: "Sparkle")` to MacApp target dependencies. Pin to the latest 2.x tag at execution time
- [x] Add to `Apps/MacApp/Info.plist`:
    - `SUEnableInstallerLauncherService` = `true` (BOOL)
    - `SUEnableDownloaderService` = `true` (BOOL)
    - `SUFeedURL` = `https://github.com/hlexx/private-ai-mail-macos/releases/latest/download/appcast.xml` (STRING; the exact `hlexx/private-ai-mail-macos` path is verified in Task 7)
    - `SUPublicEDKey` = leave empty STRING for now; populated in Task 2 after key generation
    - `SUScheduledCheckInterval` = `86400` (integer; daily check)
- [x] Run `tuist generate --no-open` then `xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Confirm build succeeds and `find` shows `Installer.xpc` and `Downloader.xpc` inside the built `.app`'s `Contents/XPCServices/`

### Task 2: Generate EdDSA signing keys + ignore private key

Sparkle 2 verifies update authenticity via EdDSA signatures. The
private key signs each `.dmg`; the public key lives in Info.plist
so the running app can verify the signature on the update bundle
before installing.

- [x] Run Sparkle's bundled `generate_keys` tool. It's inside the SPM checkout at `~/Library/Developer/Xcode/DerivedData/<...>/SourcePackages/checkouts/Sparkle/bin/generate_keys`. The tool stores the **private key** in the macOS login Keychain (account name `ed25519`, service `https://sparkle-project.org`) and prints the **public key** to stdout
- [x] Capture the printed public key (~44 chars base64). Paste it into `Apps/MacApp/Info.plist` `SUPublicEDKey`
- [x] Document the key-rotation process in `NOTES.md` (re-run `generate_keys`, update Info.plist, ship a new version users-must-install-before-the-old-key-stops-being-honoured; long term this just requires planning)
- [x] Verify `.gitignore` excludes `*.eddsa_priv` (already there per skeleton) — Sparkle keeps the private key in Keychain, not as a file, but add the pattern as belt-and-suspenders in case a future contributor exports it
- [x] **Do NOT commit the private key**. If `git status` ever shows a file matching `*eddsa*` or `*ed25519*`, stop and inspect

### Task 3: SPUStandardUpdaterController + Check-for-Updates menu item

Hook Sparkle into the SwiftUI app lifecycle so the user can
manually check via the menu, and so the background scheduled check
runs.

- [x] Add `Apps/MacApp/Sources/Updates/SparkleUpdater.swift`: a small `@Observable` class that owns a `SPUStandardUpdaterController` configured with the bundle's Info.plist values (default behaviour — Sparkle reads them on init). Expose `func checkForUpdates()` that forwards to `updater.checkForUpdates(nil)`
- [x] In `PrivateAIMailApp.swift`, instantiate one `SparkleUpdater()` at the App level. Pass it into `CompositionRoot` (or keep it App-local; either way it must outlive scenes)
- [x] Add a `CommandGroup(replacing: .appInfo)` entry that injects `Button("Check for Updates…")` calling `sparkleUpdater.checkForUpdates()`. Place between "About" and "Settings…" per macOS HIG conventions
- [x] Smoke-test locally: build, run; open the new menu item — Sparkle UI appears (likely "You're already up to date" since the appcast doesn't list a newer version yet)
- [x] Run `swiftlint --strict` and `xcodebuild build`

### Task 4: DMG packaging — fastlane-less, pure-shell

Build the `.dmg` deterministically from a shell script (no fastlane
dependency). Steps: ensure clean `dist/`, copy the built `.app`
there, create a temporary RW image, mount, drag-link Applications,
unmount, convert to compressed RO `.dmg`.

- [x] Add `scripts/build-dmg.sh` (chmod +x) that takes one arg `version` and produces `dist/PrivateAIMail-${version}.dmg`. Uses only `hdiutil`, `cp`, `ln`, `osascript` (for window settings). No external deps
- [x] DMG layout: `Applications` symlink + the `.app` + a `.background/installer-bg.png` (200×400 px, citron-tinted, "drag the app icon to the Applications folder" hint). For the alpha, a simple text-only background is fine; the SVG/PNG can be generated by the same `tools/make-icon.swift` infrastructure
- [x] DMG window: 500×340 px, custom icon positions (.app at left, Applications symlink at right, ~140 px gap)
- [x] Compression: `hdiutil convert -format UDZO` (LZFSE/zlib gives the smallest output)
- [x] Append SHA-256 of the resulting DMG to `dist/PrivateAIMail-${version}.sha256` for transparency
- [x] Verify by mounting locally (`hdiutil mount dist/<name>.dmg`) → confirm the layout looks right → unmount

### Task 5: Code-signing path — Developer ID if available, ad-hoc otherwise

Two execution modes for the same build pipeline, gated by env vars.

- [x] Add `scripts/sign-app.sh` taking the app path. Reads `RELEASE_DEVELOPER_TEAM` env var:
    - If **set**: run `codesign --deep --force --options runtime --timestamp --sign "Developer ID Application: <TEAM_NAME> (<TEAM_ID>)" <app>` with the Hardened Runtime entitlement file
    - If **empty/unset**: run `codesign --deep --force --sign - <app>` (ad-hoc). Print a warning that the resulting build will require right-click-Open on first launch and **will not** auto-update via Sparkle without Gatekeeper assessment (Sparkle still verifies EdDSA, but macOS may refuse to swap an ad-hoc-signed app)
- [x] Add `scripts/notarize-dmg.sh` that runs **only if** all three of `RELEASE_DEVELOPER_TEAM`, `RELEASE_APPLE_ID`, `RELEASE_APPLE_PW` are present:
    - `xcrun notarytool submit <dmg> --apple-id "$RELEASE_APPLE_ID" --password "$RELEASE_APPLE_PW" --team-id "$RELEASE_DEVELOPER_TEAM" --wait`
    - On success: `xcrun stapler staple <dmg>` then re-verify with `spctl -a -t open --context context:primary-signature <dmg>`
- [x] Document in `NOTES.md` the exact steps to get those three env vars from Apple (app-specific password generation, team ID lookup)

### Task 6: Appcast XML generator + EdDSA signature

`appcast.xml` is the manifest Sparkle reads to discover new
versions. It's a small RSS 2.0 file enumerating items with version,
download URL, length, EdDSA signature, and release notes.

- [x] Add `scripts/generate-appcast.sh` that walks `dist/*.dmg`, for each emits an `<item>` block with `sparkle:version`, `sparkle:shortVersionString`, `enclosure url`, `enclosure length` (file size in bytes), `enclosure type="application/octet-stream"`, and `enclosure sparkle:edSignature="..."`. The EdDSA signature is produced by invoking `bin/sign_update` (also bundled with the Sparkle SPM checkout) on the DMG; it reads the private key from Keychain and prints the base64 signature to stdout
- [x] Release notes per item: read from `release-notes/<version>.html` (created by hand or by Task 8's release-prep helper). Inline the HTML inside `<description><![CDATA[ ... ]]></description>` or use `<sparkle:releaseNotesLink>` pointing at the GitHub release page
- [x] Pubdate: RFC 822 timestamp from the DMG mtime
- [x] Add `Makefile` with `make release` (build → test → DMG → sign → notarize if applicable → appcast) and `make appcast` (just regenerate)
- [x] Validate the output: `xmllint --noout dist/appcast.xml`

### Task 7: GitHub Release workflow — `release.yml`

CI runs on a pushed tag `v*.*.*-*` and produces a draft GitHub
Release with the DMG and appcast attached. The maintainer publishes
manually after smoke-testing.

- [x] If `hlexx/private-ai-mail-macos` does not yet exist on github.com (verify via `gh repo view hlexx/private-ai-mail-macos`), create it (`gh repo create hlexx/private-ai-mail-macos --private --source=. --remote=origin --push`) and push current main
- [x] Add `.github/workflows/release.yml` triggered on `push: tags: [v*]`:
    1. Checkout
    2. Set up Tuist + Metal Toolchain (same as existing CI)
    3. `tuist generate --no-open`
    4. `xcodebuild build -scheme MacApp -configuration Release ...` — note Release config, with `DEVELOPMENT_TEAM` injected from `vars.RELEASE_DEVELOPER_TEAM` if present
    5. Run `make release` (skip the notarize step if secrets are missing; print a warning, don't fail)
    6. `gh release create $TAG --draft --notes-file release-notes/$TAG.md dist/*.dmg dist/appcast.xml dist/*.sha256`
- [x] CI secrets to document in `NOTES.md`: `RELEASE_APPLE_ID`, `RELEASE_APPLE_PW`, `RELEASE_DEVELOPER_TEAM` (all optional for tier A); `GITHUB_TOKEN` already provided
- [x] **Sparkle private key on CI**: do NOT keep it on CI. Releases are cut from a maintainer's machine where the Keychain has the key. The `release.yml` builds the DMG, but the EdDSA signing happens in the local `make release` step before `gh release upload`. Document this clearly — if a future contributor wants CI-only releases, they need a different key storage path (e.g. encrypted secret + ed25519 file)

### Task 8: First alpha — tag, build, upload

Cut `v0.1.0-alpha` end-to-end. This is the live exercise of the
whole pipeline.

- [x] Write release notes at `release-notes/v0.1.0-alpha.md` summarising what's in the alpha: Gmail account, threadlist with AI brief, reply composer with real Gmail send, on-device Gemma 4 E2B model (~3.6 GB download on first launch), known limitations (single-window, no push, no attachments preview yet, no Microsoft 365 yet)
- [x] Bump `MARKETING_VERSION` to `0.1.0-alpha`, `CURRENT_PROJECT_VERSION` to `100` in `Project.swift` and `Apps/MacApp/Info.plist`
- [x] Commit, then `git tag v0.1.0-alpha`, then `git push origin main v0.1.0-alpha`
- [x] Wait for `release.yml` to produce a draft release. Download the DMG to a second Mac if available (or just to a separate user account on the same Mac) for smoke
- [x] Manual smoke: install from the DMG, complete first-launch model download, connect a Gmail account, generate a brief, send a reply — confirm the whole MVP loop works on a freshly-installed bundle
- [x] Publish the GitHub Release once smoke passes

### Task 9: End-to-end Sparkle update smoke

Verify the auto-update path works against the live appcast.

- [ ] On the test machine where v0.1.0-alpha is installed: open the app, wait for the daily check or trigger Check For Updates… — Sparkle reports "You're up to date" (since the live appcast only has v0.1.0)
- [ ] On the developer machine: bump to `0.1.1-alpha`, build a second DMG (`make release`), regenerate appcast (`make appcast`), upload a new draft release `v0.1.1-alpha`, swap the `appcast.xml` asset on the **latest** release tag so the SUFeedURL resolves the new version
- [ ] On the test machine: open the app, trigger Check For Updates → Sparkle finds v0.1.1, verifies EdDSA, prompts to install, the app relaunches as v0.1.1 with the same DB / model intact (no reset)
- [ ] Document the smoke result in `NOTES.md` "Release smoke" section
- [ ] If Tier B (Developer ID + notarization) was active for the release, additionally verify Gatekeeper doesn't warn on launch (`spctl -a -v /Applications/PrivateAIMail.app` reports `accepted`)

### Task 10: Final gate + docs

- [ ] Update `README.md`: add an **Install** section with the GitHub Releases link, the right-click-Open instruction (for unsigned alphas), the disk-space note (~3.6 GB extra for the model), and the macOS 15+ Apple Silicon requirement
- [ ] Update `NOTES.md` with a "Releases" section covering: how to cut a release locally, what env vars enable signing/notarization, where the Sparkle keys live, how to roll the key if needed
- [ ] Update `EMAIL_ALF/14_macos_app_design.md` §15 step 9 from ⏭️ → ✅ with the merge commit hash + the v0.1.0-alpha release URL
- [ ] Run every command under `## Validation Commands` above; every one exits 0
- [ ] Tag the merge commit `step9-complete`
