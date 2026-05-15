# Private AI Mail — macOS

Native macOS client for **Private AI Mail**: a privacy-first AI email client
where all AI runs on-device and revenue comes from workflow integrations.

Product strategy, threat model, and roadmap live in the spec repo: see
[`EMAIL_ALF`](../EMAIL_ALF) (sibling directory). Architectural decisions for
this codebase are documented in
[`EMAIL_ALF/14_macos_app_design.md`](../EMAIL_ALF/14_macos_app_design.md) (v0.2).

## Status

**Step 4 complete.** Gmail read-only sync and on-device AI thread briefs via
MLX + Gemma are merged. The app generates per-thread briefs locally on Apple
Silicon with zero network traffic at inference time. First launch downloads
the model (~3.6 GB).

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
# Generate the Xcode workspace
tuist generate

# Or build a single package from the command line
cd Packages/Mail/MailDomain && swift test
```

Open `PrivateAIMail.xcworkspace`, select the `MacApp` scheme, run.

The app opens a single window with a 3-pane `NavigationSplitView` placeholder
(Accounts/Folders | Threads | Reading). No data flows yet.

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
- **Single-writer DB pattern.** Persistence writes go through `@DatabaseActor`
  (not yet implemented; placeholder lives in `Persistence` package).
- **Module names avoid collision with Apple frameworks.** The Core package
  is `AppFoundation`, not `Foundation`.

## Bundle ID

`com.hlexx.privateaimail` (temporary, under personal Apple Developer account).
Will be renamed at first public release.

## License

Proprietary. All rights reserved.
