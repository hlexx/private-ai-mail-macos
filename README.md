# Private AI Mail — macOS

Native macOS client for **Private AI Mail**: a privacy-first AI email client
where all AI runs on-device and revenue comes from workflow integrations.

Product strategy, threat model, and roadmap live in the spec repo: see
[`EMAIL_ALF`](../EMAIL_ALF) (sibling directory). Architectural decisions for
this codebase are documented in
[`EMAIL_ALF/14_macos_app_design.md`](../EMAIL_ALF/14_macos_app_design.md) (v0.2).

## Install

Download the latest `.dmg` from
[GitHub Releases](https://github.com/hlexx/private-ai-mail-macos/releases).

1. Mount the DMG and drag **PrivateAIMail.app** to `/Applications`.
2. Unblock Gatekeeper — this build is ad-hoc-signed (no Apple Developer
   ID yet), so macOS will show "Apple could not verify PrivateAIMail is
   free of malware." Pick one path:

   **Terminal (one line):**
   ```sh
   xattr -d com.apple.quarantine /Applications/PrivateAIMail.app
   ```
   then double-click the app as usual.

   **GUI:** double-click the app → click **Done** on the warning →
   open **System Settings → Privacy & Security** → scroll to the
   blocked-app row → click **Open Anyway**.

   The legacy *right-click → Open* override worked on macOS 14 and
   older. Apple removed it for quarantined ad-hoc apps in macOS 15
   (Sequoia), so use one of the two paths above.
3. The app downloads the on-device AI model (~3.6 GB) on first launch.
   This is a one-time download stored in
   `~/Library/Application Support/PrivateAIMail/models/`.
4. Subsequent updates are delivered automatically via Sparkle. Check
   manually via the app menu: **PrivateAIMail > Check for Updates...**

**Requirements:** macOS 15+, Apple Silicon (M1 or later), ~4 GB free disk
space for the app + AI model.

## Status

**Step 9 complete.** First installable alpha (v0.1.0-alpha) released with
Sparkle auto-update support. Gmail read-only sync, on-device AI thread
briefs via MLX + Gemma, reply composer with real Gmail send. The app
generates per-thread briefs locally on Apple Silicon with zero network
traffic at inference time.

## Requirements

- macOS 15+ (deployment target; will bump to 26 once `FoundationModels` is
  required at runtime)
- Apple Silicon
- Xcode 16+ / Swift 6
- [Tuist](https://docs.tuist.dev) 4.x (`brew install tuist`)
- Metal Toolchain for local builds: `sudo xcodebuild -downloadComponent MetalToolchain`
- ~3.6 GB disk space for on-device AI model (downloaded automatically on first launch)

## Quickstart

```bash
# Download Sparkle xcframework (one-time, not committed to repo)
./scripts/fetch-sparkle.sh

# Generate the Xcode workspace
tuist generate

# Or build a single package from the command line
cd Packages/Mail/MailDomain && swift test
```

Open `PrivateAIMail.xcworkspace`, select the `MacApp` scheme, run.

The app opens the Re:Box mail workspace with Gmail account connection, folder
filters, thread reading, local AI briefs, reply drafting, and Gmail send.

## Repo layout

```
Apps/
  MacApp/           # @main, scenes, composition root
  iOSApp/           # placeholder (not built in MVP)
Packages/
  Core/             # AppFoundation, DesignSystem, Persistence
  Mail/             # MailDomain, MailProviders, MailIndex, MailSync
  AI/                # AIPrompts, AIEmbeddings, AIRuntime, AIKit, AIEvals
  Attachments/      # AttachmentKit, AttachmentRAG
  Auth/             # AuthKit
  Integrations/     # IntegrationDomain, IntegrationBroker, IntegrationConnectors
  Features/         # InboxFeature, ThreadFeature, ComposeFeature,
                    # BriefFeature, ActionsFeature, SettingsFeature
Tuist/              # generation config
Project.swift       # MacApp target manifest (consumed by Tuist)
```

24 SwiftPM packages total. Dependency graph follows the layered architecture
in §4 of the design doc.

## Conventions

- **Swift 6 strict concurrency** is enabled project-wide.
- **No raw string literals in SwiftUI `Text(...)`** — wrap with
  `String(localized:)`. Enforced by a SwiftLint custom rule.
- **One `xcstrings` catalog per package** under `Sources/<Name>/Resources/`.
  MVP ships `en` only, but every package is i18n-ready (see §14.1 of the
  design doc).
- **Single-writer DB pattern.** Persistence writes that cross concurrency
  boundaries go through `@DatabaseActor` in the `Persistence` package.
- **Module names avoid collision with Apple frameworks.** The Core package
  is `AppFoundation`, not `Foundation`.

## Bundle ID

`com.hlexx.privateaimail` (temporary, under personal Apple Developer account).
Will be renamed at first public release.

## License

Proprietary. All rights reserved.
