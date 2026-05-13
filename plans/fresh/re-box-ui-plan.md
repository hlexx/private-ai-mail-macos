# Re:Box macOS UI — pixel-perfect implementation

## Overview

Implement the **Re:Box** design handoff (Claude Design HTML/CSS/JSX prototype)
in the existing SwiftUI macOS app. Pixel-perfect: bundle the three web fonts
(Geist, Instrument Serif, JetBrains Mono), replicate the OKLCH color palette
(graphite + citron + cobalt + violet + state tones), and rebuild every screen
component: custom toolbar with transparent titlebar, sidebar, threadlist with
filter chips and signal chips, reading pane with thread + attachment +
inline composer + AI brief rail, the ⌘K action sheet overlay, and the
full-screen compose window.

Step 3 (Gmail read-only sync) just merged into `main` (commit `f79b287`).
Real Gmail data is flowing through `InboxStore` / `ThreadStore` via GRDB
`ValueObservation`. The job now is to redress everything visually to match
Re:Box without breaking that data flow.

## Context

- Handoff bundle: `Re_BOX-handoff (2).zip` (118 KB), extracted by ralphex into
  `design/re-box/` in repo (see Task 1).
  - Primary design file: `design/re-box/project/Re:Box macOS.html`. Read it
    first; it imports `app/data.js`, `app/Icon.jsx`, `app/Toolbar.jsx`,
    `app/Sidebar.jsx`, `app/ThreadList.jsx`, `app/AIBrief.jsx`,
    `app/ReadingPane.jsx`, `app/ActionSheet.jsx`, `app/Composer.jsx`,
    `app/App.jsx` and stylesheets `app/app.css` + `app/colors_and_type.css`.
  - Light theme variant: same files with `data-theme="light"`.
  - Alternative reading-pane explorations: `Re:Box ReadingPane v2.html` +
    `app/cards-v2.{jsx,css}` — **out of scope** for this iteration.
  - Wireframes: `Re:Box Wireframes.html` + section1–section4 files — **also
    out of scope**.

- Existing codebase to redress (do not rewrite the data layer):
  - `Apps/MacApp/Sources/Scenes/MainScene.swift` — currently uses
    `NavigationSplitView` with sidebar (real accounts) → `InboxView` →
    `ThreadView`. Bound to a `ValueObservation` of `AccountRecord`.
  - `Apps/MacApp/Sources/Scenes/SettingsScene.swift` — Accounts/Privacy/AI tabs;
    Accounts tab wired to `AccountsTab` from `SettingsFeature`.
  - `Apps/MacApp/Sources/PrivateAIMailApp.swift` — `@main`, single `WindowGroup`,
    keyboard shortcut for compose (currently no-op).
  - `Apps/MacApp/Sources/CompositionRoot.swift` — owns `AppDatabase`,
    `InboxStore`, `ThreadStore`, `AccountsTabStore`, `SyncSupervisor`.
  - `Packages/Core/DesignSystem/Sources/DesignSystem/DesignSystem.swift` —
    stub `public enum DesignSystem { public static let moduleName = "DesignSystem" }`.
    Nothing else.
  - `Packages/Features/InboxFeature/` — has `InboxStore` + `InboxView` rendering
    real threads via `ValueObservation`. Visual is minimal.
  - `Packages/Features/ThreadFeature/` — has `ThreadStore` + `ThreadView` showing
    raw plain-text messages.
  - `Packages/Features/BriefFeature/` — empty stub. Brief Rail lands here.
  - `Packages/Features/ActionsFeature/` — empty stub. Action Sheet lands here.
  - `Packages/Features/ComposeFeature/` — empty stub. Compose window lands here.
  - `Packages/Features/SettingsFeature/` — has real `AccountsTab`. Keep as-is.
  - `Apps/MacApp/Resources/Localizable.xcstrings` — small set of strings;
    new UI strings get added here (or in feature-package catalogs).

- §14 design doc decisions still apply: Swift 6 strict concurrency, GRDB,
  NSTextView for rich-text composer, no MLX yet, en-only with i18n-readiness.

- AI is not yet wired (§15 step 4). Brief Rail and tone-rewriter in the
  composer show **hardcoded stub data** for the first two thread fixtures
  during this iteration. A `// TODO(§15-step-4): remove stub when AIKit lands`
  comment marks every stub site.

- Pixel measurements pulled directly from `design/re-box/project/app/app.css`
  during implementation; do not eyeball.

## Success Criteria

- Window matches the design: 56 px toolbar with transparent NSWindow titlebar
  and traffic-light overlap; main pane is a 3-column layout sized
  **240 px sidebar + 360 px threadlist + 1fr reading**; inside the reading
  pane the brief rail is **340 px** wide.
- Design system in `DesignSystem` package exports semantic color tokens
  (`Color.rbBgCanvas`, `Color.rbFg1`, `Color.rbCitron500`, …) backed by
  OKLCH→sRGB conversions and switching automatically by `ColorScheme`.
- Three web fonts bundled and registered: Geist (400/500/600/700), Instrument
  Serif (regular + italic), JetBrains Mono (400/500/600). Available as
  `Font.rbGeist(size:weight:)`, `Font.rbSerifItalic(size:)`, `Font.rbMono(size:)`.
- Every signal-chip variant from the design renders: `due` (with `urgent` flag),
  `reply`, `att`, `ai`, `logged`, `cc`, `cal`, `paid`. Color/contrast matches.
- Toolbar: custom account switcher pill (cycles accounts on click), search
  pill with ⌘K hint, four icon buttons (filter / theme toggle / settings /
  compose). Theme toggle persists via `@AppStorage`.
- Sidebar: Mail section (folder rows with SF Symbol + name + optional count
  badge), Accounts section (color-dot + email), Privacy footer with
  "Local AI · M-series" pill.
- ThreadList: header (Inbox + meta), horizontal filter-chip row, thread
  rows with gradient avatar, from + account label, subject, preview, signal
  chips, time. Active row gets a 3 px citron bar on its left edge.
- ReadingPane: subject head + meta + Archive/Snooze/Send-to buttons; message
  stack rendering avatar + name + time + body; attachment block when present;
  inline composer with tone segment + textarea + citations + Regenerate/
  Edit-in-full/Send; brief rail on the right with eyebrow + confidence +
  summary + fields + evidence + CTAs (or empty state).
- ⌘K opens a centered Action Sheet modal: 4×2 grid of action tiles, picking
  one shows a "Re:Box will …" preview block with mock 5-second undo line.
- ⌘N opens a full-screen Composer window: `NSTextView`-backed rich-text body,
  to/cc/subj header rows, footer with metadata + Save draft / Rewrite / Send.
- Light theme parity: every component renders correctly when system
  appearance is light (or when toolbar toggle is set to light). Snapshot
  tests cover both themes for major views.
- `xcodebuild build -scheme MacApp` exits with `** BUILD SUCCEEDED **`.
- `swiftlint --strict` reports 0 violations.
- All per-package `swift test` runs exit 0, including new snapshot tests for
  DesignSystem atoms and major feature views.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && tuist generate --no-open`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && swiftlint --strict`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Core/DesignSystem && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Features/InboxFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Features/BriefFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Features/ActionsFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Features/ComposeFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build`

### Task 1: Vendor the design source into the repo and bundle web fonts

Get the design handoff and required fonts into the repo so subsequent tasks
have stable paths to read and so the app can load fonts from its bundle.

- [x] If `/tmp/re-box-inspect/re-box/` is missing, recreate it via `mkdir -p /tmp/re-box-inspect && cd /tmp/re-box-inspect && unzip -q '/Users/alexeykhaynovsky/Downloads/Re_BOX-handoff (2).zip'`
- [x] Copy `/tmp/re-box-inspect/re-box/` → `design/re-box/` at repo root (excluding `project/uploads/PRIVATE_AI_MAIL_FULL_DOCUMENTATION.md`, which duplicates `EMAIL_ALF/`)
- [x] Add `design/README.md` linking back to `EMAIL_ALF/14_macos_app_design.md` and explaining that `design/re-box/` is the source of truth for this iteration
- [x] Download these OFL font files into `Apps/MacApp/Resources/Fonts/`:
  - Geist Variable (or static 400/500/600/700) — `https://github.com/vercel/geist-font/raw/main/packages/next/dist/fonts/geist-sans/` or Google Fonts download
  - Instrument Serif Regular + Italic — `https://fonts.google.com/specimen/Instrument+Serif`
  - JetBrains Mono 400/500/600 — `https://www.jetbrains.com/lp/mono/`
- [x] Register fonts in `Apps/MacApp/Info.plist` via `ATSApplicationFontsPath` set to `Fonts`
- [x] Update `Apps/MacApp/Resources/Assets.xcassets/` is unchanged; do NOT add the fonts there
- [x] Add `Apps/MacApp/Resources/Fonts/LICENSES.txt` consolidating the three OFL license files
- [x] Run `tuist generate --no-open && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` and confirm the app bundle contains all three font families: `ls /Users/alexeykhaynovsky/Library/Developer/Xcode/DerivedData/PrivateAIMail-*/Build/Products/Debug/PrivateAIMail.app/Contents/Resources/Fonts/ | head -20` shows the .otf/.ttf files

### Task 2: DesignSystem color tokens, surfaces, and theme switching

Build the color/surface foundation in `DesignSystem`. Read
`design/re-box/project/app/colors_and_type.css` sections 2–4 verbatim and
translate every OKLCH variable into a sRGB `Color` value with the same name.

- [x] Create `Packages/Core/DesignSystem/Sources/DesignSystem/Tokens/Colors.swift` with `extension Color` exposing `rbGraphite50..rbGraphite950`, `rbCitron300..rbCitron700`, `rbCobalt300..rbCobalt600`, `rbViolet400..rbViolet600`, `rbChrome200..rbChrome400`, `rbToneAmber{300,500}`, `rbToneCoral{400,600}`, `rbToneJade{400,600}`, `rbToneIce{400,600}`. Compute each from the CSS OKLCH triple using a Swift OKLCH→sRGB helper (or pre-compute to hex with a comment showing the source OKLCH)
- [x] Add `OKLCH.swift` helper with `static func toSRGB(l:c:h:) -> (r: Double, g: Double, b: Double)` matching the CSS-Color-4 algorithm; cover with a unit test that pins known triples to expected sRGB triplets within 1/255 tolerance
- [x] Create `Packages/Core/DesignSystem/Sources/DesignSystem/Tokens/Surfaces.swift` with semantic accessors `Color.rbBgDeep`, `rbBgCanvas`, `rbBgElev1`, `rbBgElev2`, `rbBgElev3`, `rbBgInverse`, `rbFg1`, `rbFg2`, `rbFg3`, `rbFg4`, `rbFgInverse`, `rbFgOnAccent`, `rbStroke1`, `rbStroke2`, `rbStrokeFocus`, `rbAccent`, `rbAccentHover`, `rbAccentPress`, `rbAccentSoft`, `rbAccentSecondary`, `rbAccentTertiary`, plus signal pairs `rbSignalReply` / `rbSignalReplyBg`, `rbSignalDeadline` / `rbSignalDeadlineBg`, `rbSignalAttach` / `rbSignalAttachBg`, `rbSignalSuccess` / `rbSignalSuccessBg`, `rbSignalLocalAi` / `rbSignalLocalAiBg`, plus glass tokens `rbGlassThin`, `rbGlassThick`, `rbGlassStroke`, `rbGlassHighlight`. Each one resolves to the correct value for the current `ColorScheme` via a `Color` initializer that branches on `Color(NSColor(name:dynamicProvider:))`
- [x] Create `Packages/Core/DesignSystem/Sources/DesignSystem/Theme/Theme.swift` with `enum Theme { case system, dark, light }` and an `@AppStorage("rb-theme")` wrapper that maps Theme → preferred `ColorScheme` for the root view
- [x] Add `Packages/Core/DesignSystem/Tests/DesignSystemTests/ColorsTests.swift`: verify the OKLCH conversion against three reference triplets, verify semantic surfaces resolve differently in dark vs light traits using `NSAppearance`
- [x] Run `cd Packages/Core/DesignSystem && swift test`

### Task 3: DesignSystem typography, spacing, radii, motion

Translate sections 5–6 of `colors_and_type.css` into Swift `Font` + constant
helpers usable from any feature package.

- [x] Create `Packages/Core/DesignSystem/Sources/DesignSystem/Tokens/Typography.swift` with `extension Font`: `rbGeist(_ size: CGFloat, weight: Font.Weight = .regular)`, `rbSerifItalic(_ size: CGFloat)`, `rbMono(_ size: CGFloat, weight: Font.Weight = .regular)`. Each registers and returns the bundled font with a system fallback chain (`-apple-system, "SF Pro Text"` for Geist, etc.)
- [x] Add `enum RBTextStyle { case displayXL, displayLG, displayMD, h1, h2, h3, h4, bodyLG, body, bodySM, label, eyebrow, mono, editorial }` plus a `View.rbTextStyle(_:)` modifier applying font + line spacing + tracking from the CSS
- [x] Create `Packages/Core/DesignSystem/Sources/DesignSystem/Tokens/Spacing.swift` with `enum RBSpace { static let s1: CGFloat = 4; s2 = 8; … s20 = 80 }`
- [x] Create `Packages/Core/DesignSystem/Sources/DesignSystem/Tokens/Radii.swift` with `enum RBRadius { static let xs: CGFloat = 4; sm = 6; md = 10; lg = 14; xl = 20; xl2 = 28; pill = 999 }`
- [x] Create `Packages/Core/DesignSystem/Sources/DesignSystem/Tokens/Motion.swift` with `enum RBDuration` (`d1 = 0.12; d2 = 0.20; d3 = 0.32; d4 = 0.48`) and `enum RBEase` providing matching `Animation.timingCurve` values
- [x] Add snapshot tests in `DesignSystemTests` that render a "Tokens Cheatsheet" view (color swatches + every text style + spacing grid) in dark and light; commit the baseline snapshots
- [x] Run `cd Packages/Core/DesignSystem && swift test`

### Task 4: DesignSystem atoms (chips, buttons, pills, fields)

Build the reusable components that show up in many places. All atoms live in
`DesignSystem` so feature packages stay thin.

- [x] `SignalChip.swift` exposing `SignalChip(kind:)` with cases `.due(label, urgent)`, `.reply(label)`, `.att(pages)`, `.ai(label)`, `.logged(target)`, `.cc(label)`, `.cal(label)`, `.paid(label)`. Each variant maps to the corresponding `rbSignal*` color/background pair, includes an SF Symbol leading icon, and uses `RBTextStyle.eyebrow` for the trailing label
- [x] `RBButtonStyle.swift` with `.primary`, `.secondary`, `.ghost` `ButtonStyle`s; primary uses `rbAccent` background + `rbFgOnAccent` text; ghost is transparent with `rbFg2` text + hover background
- [x] `RBIconButton.swift` — square button hosting an SF Symbol, 28×28, `rbBgElev1` hover background, accessibility label parameter
- [x] `LocalAIPill.swift` — pill with a 6 px citron dot + "Local AI · M-series" text, `rbSignalLocalAiBg` background
- [x] `AccountSwitcher.swift` — pill with a color-dot + label + chevron, tappable; takes `Account` + `onCycle` closure
- [x] `SearchField.swift` — pill containing a magnifying-glass SF Symbol, a `TextField` with placeholder "Search or ask Re:Box (last week, contracts, due Friday…)", and a trailing ⌘K keyboard-shortcut hint label
- [x] `EyebrowLabel.swift` — mono uppercase tracking-eyebrow label, used for "Re:Box brief · local", "Drafted locally · tone:", etc.
- [x] `AvatarView.swift` — circle avatar with optional linear-gradient background (matches `t.fromColor` lin-gradient pattern) and 2-letter initials
- [x] Snapshot tests in `DesignSystemTests` for every atom × dark+light
- [x] Run `cd Packages/Core/DesignSystem && swift test`

### Task 5: Custom window chrome and top Toolbar

Replace the default macOS title bar with a transparent unified bar; build
the Re:Box top toolbar (56 px high, blurred glass background, traffic-light
overlap, account switcher, search, action icons).

- [x] Update `Apps/MacApp/Sources/PrivateAIMailApp.swift` to apply `.windowStyle(.hiddenTitleBar)`, `.windowToolbarStyle(.unifiedCompact(showsTitle: false))`, and a transparent background using `NSWindow` introspection (window.titlebarAppearsTransparent = true, window.titleVisibility = .hidden, window.styleMask insert .fullSizeContentView)
- [x] Create `Apps/MacApp/Sources/Views/RBToolbar.swift` rendering the 56 px bar: an `HStack` with leading 240 px region containing the `AccountSwitcher`, trailing region with `SearchField` (max width 480 px) and four `RBIconButton`s (filter, theme toggle sun/moon, settings gearshape, compose pencil)
- [x] Background: `.background(.regularMaterial)` (NSVisualEffectView equivalent) with `rbStroke1` bottom border to match the CSS `backdrop-filter: blur(24px)`
- [x] Wire account cycling: tapping the `AccountSwitcher` rotates through accounts from `AppDatabase` via `CompositionRoot.activeAccountID` (new property)
- [x] Wire theme toggle: changes `@AppStorage("rb-theme")` between dark/light/system; the root view watches it and applies `.preferredColorScheme(...)`
- [x] Wire compose button + `⌘N` shortcut → opens Composer window (Task 11 will fill behavior; stub for now)
- [x] Wire `⌘K` shortcut to toggle a state binding `showActionSheet` (Task 10 fills behavior)
- [x] Hide the system `Edit` / `Format` / `Window` menu items not relevant to email — leave the `App` `View` `Window` menus default
- [x] Add snapshot tests for `RBToolbar` in dark+light, with and without accounts loaded
- [x] Run all validation commands

### Task 6: Sidebar redesign (Mail / Accounts / Privacy)

Replace the current `NavigationSplitView` sidebar with the Re:Box sidebar.
Keep the existing account observation; swap the visual layout.

- [x] Create `Apps/MacApp/Sources/Views/RBSidebar.swift` taking a `SidebarStore` view-model exposing `folders: [FolderItem]` and `accounts: [AccountRow]`
- [x] Add `FolderItem` and `AccountRow` types in `Packages/Features/InboxFeature/` (or a new `Packages/Features/SidebarFeature/` if cleaner — choose one and stay consistent)
- [x] Hard-code folder list to match the design data: Inbox, Needs reply, Has deadline, Attachments, Logged, Starred, Sent, Archive. Counts pull from real DB queries where applicable (Inbox = unread count; others may be 0/nil at this stage)
- [x] Render folder rows: SF Symbol leading icon + name + optional count badge (right-aligned, `rbBgElev2` rounded background)
- [x] Render accounts list using existing observation of `AccountRecord`; each row has a colored dot derived deterministically from `account.id` hash + email text
- [x] Add `LocalAIPill` to footer
- [x] Replace sidebar invocation in `MainScene.swift` to use `RBSidebar` with width 240 (explicit `.frame(width: 240)`)
- [x] Snapshot tests for `RBSidebar` in dark+light
- [x] Run all validation commands

### Task 7: ThreadList redesign + filter chips

Reskin `InboxFeature/InboxView` to match the design's threadlist column.

- [x] Update `Packages/Features/InboxFeature/Sources/InboxFeature/InboxView.swift` to render: header (`Inbox` title + meta "N threads · M need reply"), horizontal scroll of `RBFilterChip` (All / Needs reply / Has deadline / Attachments / AI handled), then the list rows
- [x] Add `RBFilterChip.swift` in DesignSystem (a smaller cousin of SignalChip — pill that toggles between off/on with `rbBgElev1` vs `rbAccentSoft` background)
- [x] Add filter state on `InboxStore`: `filter: ThreadFilter` (`.all` / `.needsReply` / `.hasDeadline` / `.hasAttachment` / `.aiHandled`)
- [x] Reskin row rendering: replace current row layout with a `Grid` (avatar 32 px / body / meta) matching `.rb-row` CSS in `app.css` lines 101–115. Active row gets a 3 px citron bar on left via overlay
- [x] Row body: from line (unread dot + name + account label colored by account), subject line, preview line, optional signals row (chips from `SignalChip`)
- [x] Time on right (mono, 10.5 px, `rbFg3`)
- [x] Avatar: extract initials from `from` name, gradient background from a stable `from`-hash to `[rbCobalt500, rbViolet500]` or similar
- [x] Since real Gmail data does not include chip metadata (deadline / has-attachment / etc.), derive chips from `ThreadRow` fields when possible (`attachmentCount > 0 → .att`), and add a `// TODO(§15-step-4): drive chips from AIKit brief` for the others. Hardcoded stubs allowed for the first two thread fixtures during dev
- [x] Set threadlist column width 360 px in `MainScene.swift`
- [x] Snapshot tests for `InboxView` in dark+light, with and without active selection
- [x] Run `cd Packages/Features/InboxFeature && swift test`

### Task 8: ReadingPane redesign (head + thread + attachment)

Reskin `ThreadFeature/ThreadView` to match the upper portion of the Re:Box
reading pane (subject head + meta + Archive/Snooze/Send-to + message stack +
attachment block). Inline composer and brief rail are separate tasks.

- [ ] Update `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift` to wrap content in a `VStack` with: head section, scrollable thread column, optional attachment block, slot for inline composer (Task 9), all left of a `BriefRail` slot (Task 8b will glue them in MainScene)
- [ ] Head section: subject (`RBTextStyle.h2`), meta line (mono, `rbFg3`) showing `from`, `to alex@studio.eu` (use the active account email), `N messages`, optional `1 attachment`. Three ghost buttons on the right: Archive (archivebox SF Symbol), Snooze (clock), Send to ↗ (paperplane)
- [ ] Message stack: each message rendered as a card with `rbBgElev1` background, `rbStroke1` border, `RBRadius.md` corner. Header row: 28 px gradient avatar + name (bold) + time on the right (mono)
- [ ] Attachment block: a horizontal card with thumbnail placeholder (8 px radius square, `rbBgElev2`), name + meta line ("N pages · KB · summarized locally"), and ghost Preview + secondary Summarize buttons
- [ ] Color the attachment block visible only if `thread.hasAttachment` (driven by existing GRDB query; if not yet exposed, add `hasAttachment: Bool` to `ThreadRow`)
- [ ] Snapshot tests in `ThreadFeatureTests` covering: no-thread empty state, single-message thread, multi-message thread, thread with attachment
- [ ] Run `cd Packages/Features/ThreadFeature && swift test`

### Task 9: AI Brief Rail (BriefFeature) with hardcoded stubs

Build the `BriefRail` view that lives to the right of the thread column.
Use hardcoded stubs for the first two thread fixtures from the design's
`data.js`; everything else shows the "Nothing to summarize" empty state.

- [ ] Create `Packages/Features/BriefFeature/Sources/BriefFeature/ThreadBriefViewData.swift` matching the design data shape: `summary`, `request`, `deadline`, `risk`, `nextStep`, `confidence: Double`, `evidence: [String]`. All `String?` except confidence
- [ ] Create `Packages/Features/BriefFeature/Sources/BriefFeature/BriefStore.swift` `@Observable` exposing `brief: ThreadBriefViewData?` and `loadBrief(forThreadID:)`. Stub implementation matches the design data: returns a brief for thread IDs ending in `t1` or `t2`, returns nil otherwise. Each function gets a `// TODO(§15-step-4): replace stub with AIKit.threadBrief()` comment
- [ ] Create `BriefRail.swift` rendering: eyebrow "◆ Re:Box brief · local" + confidence pill on right, summary text (`RBTextStyle.bodyLG`), grid of 4 fields with mono uppercase keys ("Request", "Deadline", "Risk", "Next step") + value (deadline gets `rbSignalDeadline` color), evidence mono line, three CTAs (primary "Draft reply", secondary "Snooze to Fri AM", ghost "Log to CRM")
- [ ] Empty state: when `brief == nil`, render `rbBgElev1`-backed card with "Nothing to summarize — informational thread."
- [ ] Wire `BriefRail` into `MainScene.swift` to the right of `ThreadView` with `.frame(width: 340)`. Use `HSplitView` or a `HStack` — pixel-perfect 340 px right rail
- [ ] Background gradient on rail: top citron 4 % mix → canvas (matches `.rb-brief-rail` CSS)
- [ ] Snapshot tests for `BriefRail` in dark+light, with and without brief data
- [ ] Run `cd Packages/Features/BriefFeature && swift test`

### Task 10: Inline composer inside ReadingPane

Add the tone-selector composer that lives between the thread column and the
brief rail. Uses hardcoded tone-rewrites until AIKit lands.

- [ ] Create `Packages/Features/ComposeFeature/Sources/ComposeFeature/InlineComposer.swift` rendering: header row with eyebrow "Drafted locally · tone:" + a 3-segment `RBToneSegment` (Concise / Warm / Direct) showing word counts, a `TextEditor` styled with `rbBgElev1` background, footer with citations line (lock SF Symbol + "3 citations · msg_1 · msg_3 · contract.pdf p.2"), and CTAs (ghost "Regenerate" with sparkle, secondary "Edit in full", primary "Send" with paperplane)
- [ ] `RBToneSegment.swift` in DesignSystem — a 3-button segmented pill, selected state has `rbAccentSoft` background, each segment shows label + smaller word-count
- [ ] Hardcoded `draftBodies` dictionary mirroring `ReadingPane.jsx` (concise/warm/direct). Each tone change replaces the textarea contents. Add `// TODO(§15-step-4): replace with AIKit.draftReply(tone:)` comment
- [ ] "Edit in full" CTA opens the full-screen Composer window from Task 11
- [ ] "Send" is a stub that closes the composer and shows a transient toast (or no-op — the §15 step 7 implements real send)
- [ ] Wire `InlineComposer` into `ThreadView` so it appears below the thread column, above the bottom edge. Show only when `thread.brief != nil` (matches the design's behavior — composer only appears when there is something to reply to)
- [ ] Snapshot tests for `InlineComposer` in all three tone states, dark+light
- [ ] Run `cd Packages/Features/ComposeFeature && swift test`

### Task 11: Action Sheet overlay (⌘K)

Build the modal sheet that opens on ⌘K (already wired to a state binding in
Task 5).

- [ ] Create `Packages/Features/ActionsFeature/Sources/ActionsFeature/ActionSheetView.swift` rendering: header with eyebrow "What should I do with this thread?" + subject of the active thread + close `RBIconButton`, a 4×2 grid of `ActionTile` cards (each: 36 px colored icon block + label), a preview block at the bottom with eyebrow "◆ Re:Box will" + "undo in 5s" + the picked action's preview text + "on-device · 0 bytes uploaded" mono line, two CTAs at the bottom (ghost Cancel, primary "Do it")
- [ ] Action set mirrors `ActionSheet.jsx`: Draft reply (citron), Snooze to Fri (cobalt), Log to CRM (violet), Make a task (burnt orange — add this to tokens), Archive (graphite), Unsubscribe (graphite), Make a rule (graphite), Share thread (graphite)
- [ ] State: `picked: ActionID` (default `.snooze` to match design); tapping a tile sets it and the preview block updates
- [ ] Add a `burntOrange-500` to color tokens — it's referenced as `var(--burnt-orange-500)` in the design. Derive value from the design's intended palette (orange-ish OKLCH; eyeball or pick a citron-adjacent warm)
- [ ] Centered modal: `ZStack` overlay on the whole window with `.background(.ultraThinMaterial)` mask + a card sized ~620×480 px with `RBRadius.lg`
- [ ] Pressing Escape or clicking the backdrop dismisses
- [ ] Wire it into `MainScene.swift` so the binding from Task 5 controls visibility
- [ ] Snapshot tests for each picked-state in dark+light
- [ ] Run `cd Packages/Features/ActionsFeature && swift test`

### Task 12: Full-screen Compose window

Implement the standalone Compose window (⌘N opens it) with an
`NSTextView`-backed rich-text body, per §14 design decision 4.

- [ ] Create `Packages/Features/ComposeFeature/Sources/ComposeFeature/ComposeWindow.swift` — a `Scene` (or a `WindowGroup`-presented view) rendering header (subject + close button), 3 field rows (to / cc / subj), a `RichTextEditor` view, footer with metadata eyebrow ("◆ drafted locally · attached contract.pdf · tone: concise") and CTAs (ghost "Save draft", secondary "Rewrite" with sparkle, primary "Send" with arrow.up)
- [ ] Create `RichTextEditor.swift` (NSViewRepresentable wrapping `NSTextView`) supporting bold/italic/links/quote-citation via standard NSAttributedString. Implement minimum surface: bind to a `NSAttributedString` binding, sensible default font (Geist 14 px / RBSpace line height), respond to standard editing shortcuts. Real rich-text features (attachments, signatures, quote-collapse) are out of scope for this iteration
- [ ] Hook ⌘N in `PrivateAIMailApp.swift` to open the `ComposeWindow` (use `@Environment(\.openWindow)` with a registered window group)
- [ ] Snapshot test for ComposeWindow in dark+light at a few sizes
- [ ] Run `cd Packages/Features/ComposeFeature && swift test`

### Task 13: Theme parity sweep, lint, and final verification

Ensure every component renders correctly under both themes; tighten loose
ends; run the full validation gate.

- [ ] Toggle the app theme via the toolbar button and verify visually (sample each major view in light)
- [ ] Add or extend snapshot tests in `DesignSystemTests`, `InboxFeatureTests`, `ThreadFeatureTests`, `BriefFeatureTests`, `ComposeFeatureTests`, `ActionsFeatureTests` for every major view in both color schemes; commit baseline snapshots
- [ ] Replace any leftover placeholder/hardcoded copy strings with `String(localized:)` and add entries to the relevant `Localizable.xcstrings` catalog
- [ ] Run `swiftlint --strict` and fix anything it flags
- [ ] Run `grep -rE '(os_log|Logger|print|debugPrint)\(' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build` and confirm zero new logging calls in feature code (DesignSystem may have a debug pretty-print, but only inside `#if DEBUG`)
- [ ] Run `! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build` (same privacy gate as step 3)
- [ ] Run `tuist generate --no-open && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` — expect `** BUILD SUCCEEDED **`
- [ ] Run `xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme MacApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` — expect `** TEST SUCCEEDED **`
- [ ] Add a `NOTES.md` entry "Re:Box UI iteration" documenting: bundled fonts and their OFL license file location, hardcoded brief/composer stubs and which thread IDs they cover, where to find the design source (`design/re-box/`)
- [ ] Tag the merge commit `re-box-ui` after the worktree branch is squashed/merged

## Critical files to read or modify

- `design/re-box/project/Re:Box macOS.html` (Task 1 copies this from the
  extracted zip) — primary design file; everything else hangs off its imports
- `design/re-box/project/app/colors_and_type.css` — color/type/spacing/radii
  reference for Tasks 2 + 3
- `design/re-box/project/app/app.css` — layout pixel measurements for Tasks
  4–10
- `design/re-box/project/app/App.jsx`, `Sidebar.jsx`, `Toolbar.jsx`,
  `ThreadList.jsx`, `ReadingPane.jsx`, `AIBrief.jsx`, `ActionSheet.jsx`,
  `Composer.jsx`, `data.js`, `Icon.jsx` — component-level reference for each
  Task
- `Packages/Core/DesignSystem/` — Tasks 2–4 (foundation)
- `Apps/MacApp/Sources/Scenes/MainScene.swift` — gets restructured in Tasks
  5, 6, 9 (toolbar + sidebar + brief rail wiring)
- `Apps/MacApp/Sources/PrivateAIMailApp.swift` — Task 5 changes window chrome
  + adds compose window group
- `Apps/MacApp/Info.plist` — Task 1 registers `ATSApplicationFontsPath`
- `Apps/MacApp/Resources/Fonts/` — Task 1 vendors the three font families
- `Packages/Features/InboxFeature/Sources/InboxFeature/InboxView.swift` — Task 7
- `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift` —
  Task 8
- `Packages/Features/BriefFeature/Sources/BriefFeature/` — Task 9 (new files)
- `Packages/Features/ComposeFeature/Sources/ComposeFeature/` — Tasks 10 + 12
- `Packages/Features/ActionsFeature/Sources/ActionsFeature/` — Task 11

## Existing functions and utilities to reuse (do not rewrite)

- `Color.rb*` (Tasks 2 onward) — every feature package consumes these. No
  per-package color definitions
- `Font.rb*` (Tasks 3 onward) — every text style routes through these
- `SignalChip` (Task 4) — used in ThreadList (Task 7) and any future place
  showing thread signals
- `RBIconButton` (Task 4) — used by Toolbar (Task 5), ReadingPane head
  (Task 8), Action Sheet header (Task 11)
- `EyebrowLabel` (Task 4) — used by Brief Rail (Task 9), Inline Composer
  (Task 10), Action Sheet preview block (Task 11), Composer footer (Task 12)
- `InboxStore` / `ThreadStore` from step 3 — keep their public surface;
  feature views consume them via the existing `CompositionRoot`
- `SyncSupervisor` from step 3 — unchanged; the ⌘R refresh shortcut already
  wired in `PrivateAIMailApp` still applies
- `AppDatabase` from step 3 — read-only access for sidebar account list and
  brief stubs
- `KeychainTokenStore` / `GmailAPIClient` — not touched; this iteration is
  visual-only

## Verification (end-to-end)

After Task 13 succeeds, do this from a clean shell:

```bash
cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
tuist generate --no-open
xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
open ~/Library/Developer/Xcode/DerivedData/PrivateAIMail-*/Build/Products/Debug/PrivateAIMail.app
```

Inside the running app:

1. The window opens with a transparent titlebar, traffic lights overlapping
   the toolbar's left edge, and the citron-tinted radial background visible.
2. Sidebar shows Mail folders + Accounts (the one Gmail account from step 3)
   + the Local AI · M-series pill in the footer.
3. ThreadList shows real threads from the synced Gmail account, with the
   filter chip row at the top. Active row has a citron left bar.
4. ReadingPane shows subject head + thread messages + (for fixture threads
   `t1`/`t2`) a populated brief rail on the right with summary/request/
   deadline/risk/next-step/evidence/CTAs. For other threads the rail says
   "Nothing to summarize — informational thread."
5. ⌘K opens the centered Action Sheet with 8 action tiles and a live
   preview that updates as different tiles are selected.
6. ⌘N opens the full-screen Composer window with NSTextView body.
7. Switching the toolbar theme button toggles the entire UI between dark
   and light schemes. System default behavior is preserved when set to
   "system".
8. Snapshot tests for every major view exist in both dark and light
   variants, and `xcodebuild test` passes them.
