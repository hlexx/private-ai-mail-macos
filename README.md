# Private AI Mail — macOS

Native macOS client for **Private AI Mail**: a privacy-first AI email client
focused on reliable local mail workflows, explicit user approval, and
on-device AI assistance.

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

**Trust MVP release gate in progress.** The current supported provider path is
Gmail. Gmail is the stable Trust MVP provider path for account connection,
local sync/refresh, local search over synced mail, mailbox actions, attachment
metadata with narrow local preview/summary support, supervised compose/reply,
and Gmail send.

Gmail Trust MVP actions support archive, star, mark read, and trash through the
supervised action outbox. Trash requires explicit user confirmation; archive,
star, and mark-read use the fast action path. The UI shows recent pending,
running, completed, and failed action state, and retry is exposed only for
retryable failures. AI output never auto-runs an action.

Local AI reply drafting is explicit and separate from provider mutations:
selecting a thread or opening the bottom Draft panel does not generate reply
text. Draft generation starts only from Draft, Generate, Retry, or Regenerate
actions, and cached drafts may be shown without new model work. The thread and
inbox Draft actions open or focus the local inline composer; they do not create
a provider draft outbox mutation.

Outlook/Microsoft 365 support is beta-disabled in the app by default until
real-account smoke tests pass. The repo contains Microsoft Graph contracts,
OAuth configuration, mapping fixtures, sync/send adapter coverage, and
Outlook-compatible persistence rows, but the Settings UI keeps Add Outlook
disabled for this release candidate.

Local AI is an optional local assistant layer, not a provider dependency. The
current alpha includes on-device MLX + Gemma thread briefs on Apple Silicon;
mail reliability, privacy, and provider correctness are release blockers before
AI expansion.

Not supported in this Trust MVP: iCloud Mail, IMAP, JMAP, shared/delegated
mailboxes, team inboxes, CRM writes, Slack/Notion writes, send later,
auto-send, and mobile companion apps.

The reading pane can summarize supported attachments locally. Attachment
summaries are cached on device, show cited evidence from extracted chunks, and
fail instead of persisting output when evidence cannot be grounded. V1 supports
PDF text and text-like formats; DOCX, image OCR, and scanned-PDF OCR remain
unsupported.

## Requirements

- macOS 15+ (deployment target; will bump to 26 once `FoundationModels` is
  required at runtime)
- Apple Silicon
- Xcode 16+ / Swift 6
- [Tuist](https://docs.tuist.dev) 4.x (`brew install tuist`)
- SwiftLint (`brew install swiftlint`)
- ripgrep (`brew install ripgrep`)
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
and inbox thread filters available from the filter row and toolbar Filter menu,
thread reading, local search, local AI briefs, reply drafting, mailbox actions,
and Gmail send. Outlook appears as a beta provider but remains disabled until
the Trust MVP release gate records passing real-account smoke evidence.

## Validation

```bash
# Default Trust MVP release gate: diff hygiene, SwiftLint, package tests,
# privacy grep, and release-gate command guidance.
./scripts/verify-trust-mvp.sh

# Full local release gate: default gate plus Tuist generation and Debug app build.
FULL_TRUST_MVP_GATE=1 ./scripts/verify-trust-mvp.sh

# Print the gate without executing commands.
VERIFY_TRUST_MVP_DRY_RUN=1 ./scripts/verify-trust-mvp.sh
```

Run the gate with the Homebrew arm64 toolchain first on Apple Silicon if the
system PATH also contains an Intel SwiftLint binary:

```bash
PATH=/opt/homebrew/bin:$PATH ./scripts/verify-trust-mvp.sh
```

AI evals use the installed local model by default. Stub-only offline runs are
available with `RB_ALLOW_STUB_EVALS=1`, but stub output must not be used as a
baseline report.

## Local Data

The on-device model is stored under
`~/Library/Application Support/PrivateAIMail/models/`. Attachment bytes are
cached under `~/Library/Application Support/PrivateAIMail/Attachments/`, are
excluded from backup, are checksum-verified on load when metadata is available,
and are removed per account during account deletion.

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
