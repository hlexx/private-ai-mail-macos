# Step 13 — Email-client keyboard shortcuts (focus-aware) + help overlay

## Overview

The current keyboard surface (v0.1.8-alpha) is a handful of ad-hoc
shortcuts (`⌘N`, `⌘R`, `⌘K`, `⌘⇧R`, `⌃E`, `⌃S`, `⌃K`) that don't
match Apple Mail nor Gmail conventions. Mac users who hit `⌘R`
expecting Reply get a Gmail sync instead. Gmail-power-users who hit
`R` / `J` / `K` / `E` get nothing. There's no `?`-help overlay.

Step 13 rebuilds the keyboard layer to match what email users
already know:
- Apple Mail conventions for `⌘`-shortcuts (`⌘R` Reply, `⌘⇧R`
  Reply All, etc.)
- Gmail-style single-letter shortcuts when no text field is focused
  (`R`/`A`/`F` reply/reply-all/forward, `E` archive, `S` star,
  `J`/`K` thread nav, `Space` page-down + next-unread)
- A `?` overlay listing everything
- Settings → Keyboard tab as a static reference

## Context (verified 2026-05-19 against `main` at `d9717db`)

### What exists today

`grep -rn "keyboardShortcut" Apps Packages`:
- `PrivateAIMailApp.swift:54` — `⌘N` → new compose
- `PrivateAIMailApp.swift:66` — `⌘R` → refresh (`SyncSupervisor.refresh`)
- `MainScene.swift:194` — `⌘K` → ActionSheet toggle
- `MainScene.swift:197` — `⌃E` → archive
- `MainScene.swift:200` — `⌃S` → star
- `MainScene.swift:203` — `⌃K` → mark read
- `MainScene.swift:206` — `⌘⇧R` → draft reply (step12)
- `ActionSheetView.swift:199` — `Esc` → dismiss
- `MainScene.swift:321` — a custom `.keyboardShortcut(key:modifiers:action:)`
  view-modifier (the SwiftUI built-in only attaches to a button;
  this wrapper renders an invisible `Button` overlay)

### What's wrong

- **`⌘R` collides with Apple Mail's Reply convention.** Mac users
  reach for `⌘R` to reply and trigger a sync instead.
- **`⌃E` / `⌃S` / `⌃K` are non-standard.** Gmail uses single
  letters `E` / `S` / `Shift+I-U`. Apple Mail uses
  `⌘⇧A` / `⇧L` / `⌘⇧U`. Nobody uses `⌃E`.
- **No focus-aware machinery.** Adding single-letter shortcuts to
  SwiftUI views currently means typing into a TextField would
  trigger the global action. There's no infrastructure to skip
  the shortcut when a `@FocusState` is on a text input.
- **No `?`-help overlay.** Users can't discover the existing
  shortcuts.
- **Hard-coded shortcut bodies inside `MainScene`.** Action logic
  is tangled with key bindings. Adding `Reply All`, `Forward`,
  `J`/`K` nav, `⌘1/2/3` folder-jump requires ~10 more
  `.keyboardShortcut(...)` modifiers in the same view body —
  unmaintainable.
- **No `⌘⏎` for Send in compose window** (`ComposeWindowView.swift` —
  search for `Send` button; current click-only).

### What's reusable

- `composition.toastMessage` (Step 11) — for "Reply sent" / "Archived"
  feedback toasts after keyboard actions.
- `MailMutator.archive/star/markRead` (Step 10) — actions exist,
  just need new key bindings.
- `composition.replyStore.generateIfNeeded(...)` (Step 12) — Reply
  shortcut path.
- `inboxStore.selectedThreadID` / `inboxStore.threads` — for
  J/K thread navigation.
- `SidebarSelection` (Step 10) — for `⌘1/2/3/4` folder jumps.
- `Locale.current.identifier` / detected reply language (Step 10) —
  for AI draft input.

## Success Criteria

Verified on `hlexxx@gmail.com` with both English and Russian threads:

1. **`⌘R` is Reply.** Press it on any thread → inline composer
   scrolls into view, AI draft is generated. (Refresh moves to
   `⌘⇧L` and `F5`.)
2. **`R` (no modifier) also opens reply** when no text field is
   focused. Inside a TextField (composer body, search field), `R`
   types the letter as expected.
3. **`⌘⇧R` / `⇧A` is Reply All.** Composer pre-fills To: + Cc:
   with every recipient.
4. **`⌘⌥F` / `F` is Forward.** Opens a full Compose window with
   the thread quoted, To: field empty.
5. **`E` archives** (in addition to existing `⌃E` for backcompat
   for one release). Toast confirms "Archived (Undo)".
6. **`S` stars / unstars.** Visual state updates immediately.
7. **`#` or `⌘⌫` trashes** the selected thread.
8. **`J` / `K` navigate** newer / older thread in the threadlist.
   When at the bottom, J wraps to the top with a subtle haptic
   blink (no audible beep).
9. **`Space` pages down** in the reading pane. When at the
   bottom of the message, the second `Space` advances to the
   next unread thread.
10. **`⌘L` focuses search** (the Re:Box top-bar `⌘K`-style
    field). `Esc` blurs it.
11. **`⌘1` / `⌘2` / `⌘3` / `⌘4` jump** to Inbox / Starred /
    Sent / Archive respectively. `⌘5` → "All Accounts".
12. **`⌘⏎` sends from the compose window** (both full and
    inline composers).
13. **`?` opens a help overlay** listing every shortcut in
    sections (Mail / Navigation / Compose / View). `Esc` or `?`
    again dismisses.
14. **Settings → Keyboard tab** lists the same content as the
    help overlay, plus a note that future versions will allow
    remapping.

## Validation Commands

```bash
PROJ=/Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
cd $PROJ && tuist generate --no-open
cd $PROJ && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
cd $PROJ && swiftlint --strict
cd $PROJ/Packages/Features/InboxFeature && swift test
cd $PROJ/Packages/Features/ThreadFeature && swift test
cd $PROJ/Packages/Features/ComposeFeature && swift test
cd $PROJ/Packages/Features/SettingsFeature && swift test
cd $PROJ && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build
```

---

### Task 1: Keyboard-shortcut catalog (single source of truth)

Centralise every shortcut into one type so adding/removing one is
one-line and the help overlay + Settings reference are auto-generated.

- [x] Create `Apps/MacApp/Sources/Keyboard/KeyboardShortcut.swift`:
      ```swift
      enum KeyboardSection: String, CaseIterable {
          case mail, navigation, compose, view
          var title: String { ... }
      }

      struct ShortcutSpec: Identifiable {
          let id: String                    // stable, e.g. "mail.reply"
          let section: KeyboardSection
          let label: String                 // "Reply"
          let key: KeyEquivalent
          let modifiers: EventModifiers     // [] for bare-letter Gmail-style
          let scope: Scope                  // .global / .threadlist / .reading / .compose
          let requiresInputBlur: Bool       // true → only fires when no TextField focused
          let actionKey: ActionKey          // enum: reply, replyAll, forward, archive, …
      }

      enum ActionKey: String {
          case reply, replyAll, forward
          case archive, star, trash, markRead
          case threadNewer, threadOlder
          case folderInbox, folderStarred, folderSent, folderArchive, folderAll
          case pageDownOrNextUnread, focusSearch, showHelp, sendCompose
          case newCompose, refresh, actionSheet, draftReply
      }
      ```
- [x] Static `ShortcutSpec.all: [ShortcutSpec]` containing every
      entry from the table in Success Criteria (~22 specs).
- [x] Tests in `MacAppTests/KeyboardShortcutCatalogTests.swift`:
      - Every `ActionKey` case appears in `ShortcutSpec.all`.
      - No two specs share the same `(key, modifiers, scope)` triple.

### Task 2: Focus-aware shortcut dispatch

SwiftUI's `.keyboardShortcut` doesn't know about `@FocusState`. We
need a layer that consumes single-letter shortcuts ONLY when no
text input is focused.

- [x] Create `Apps/MacApp/Sources/Keyboard/KeyboardDispatcher.swift`:
      `@MainActor final class KeyboardDispatcher` with:
      - `@Observable` property `isTextInputFocused: Bool`
      - `func handle(_ key: ActionKey)` — calls the right method on
        `CompositionRoot` (or its scoped sub-stores).
      - Internal mapping `(key, modifiers) → ActionKey` derived from
        `ShortcutSpec.all`.
- [x] Create a view modifier
      `View.mailKeyboardShortcuts(dispatcher:)` that:
      - For each `ShortcutSpec` with `modifiers != []`: attaches a
        standard `.keyboardShortcut(spec.key, modifiers: spec.modifiers)`-
        decorated invisible button (existing pattern).
      - For specs with `modifiers == []` (Gmail-style bare letters):
        uses an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`
        approach (bridge via `NSViewRepresentable` + AppKit) that:
        1. Checks if `NSApp.keyWindow?.firstResponder` is an
           `NSTextView` or `NSTextField` — if yes, **does not
           consume** the event (lets it fall through to typing).
        2. Otherwise, matches against `ShortcutSpec.all`, calls
           `dispatcher.handle(...)`, returns nil to consume.
- [x] Wire `KeyboardDispatcher` into `MainScene` once; all action
      methods (`archiveSelectedThread`, `draftReply`, etc.) become
      `dispatcher.handle(.archive)` etc.
- [x] Update `MainScene` to bind `isTextInputFocused` via
      `@FocusState` observers around the search field + inline
      composer text editor (set true on focus, false on blur). This
      gives us a Swift-level signal in addition to the NSEvent
      firstResponder check.
- [x] Tests in `KeyboardDispatchTests.swift`:
      - Fire `R` while `isTextInputFocused == true` → no action.
      - Fire `R` while focus is on the thread row → dispatcher
        receives `.reply`.

### Task 3: Re-shuffle existing shortcuts to Apple-Mail conventions

Move conflicting bindings, free up the standard slots.

- [x] **Refresh** moves from `⌘R` to `⌘⇧L` (Outlook convention) +
      `F5`. Update `PrivateAIMailApp.swift:66`.
- [x] **Reply** takes `⌘R` + bare `R` (Apple Mail + Gmail).
- [x] **Reply All** takes `⌘⇧R` + bare `A` (Apple Mail + Gmail).
      `⌘⇧R` previously was Draft Reply (step12) — Draft Reply
      becomes an *alias* for Reply (functionally identical since
      our Reply IS an AI-drafted reply opening the inline composer).
      Drop the separate `draftReply` action key; map both shortcuts
      to `ActionKey.reply`.
- [x] **Forward** takes `⌘⌥F` + bare `F`. New action;
      opens the full ComposeWindow with the thread quoted in body
      and an empty To: field. Implementation: extend
      `ComposeViewModel.prefillForward(thread:)`.
- [x] **Archive**: bare `E` + keep `⌃E` for one release as alias
      (mark `⌃E` as deprecated in the help overlay).
- [x] **Star**: bare `S` + keep `⌃S` as alias.
- [x] **Trash**: bare `#` (Gmail) + `⌘⌫` (Apple Mail). New action;
      wire to `MailMutator.trash`.
- [x] **Mark read/unread**: bare `Shift+I` (read) and `Shift+U`
      (unread) — Gmail convention.
- [x] Snapshot test in `KeyboardCatalogSnapshotTests`: the help
      overlay rendered with the new catalog matches a committed
      `.txt` baseline so future regressions to the catalog show up
      in code review.

### Task 4: Thread navigation — J/K + Space-then-next-unread

- [x] Implement `ActionKey.threadNewer` / `.threadOlder` in
      `KeyboardDispatcher`:
      ```swift
      func navigateThread(direction: ThreadNavDirection) {
          guard let active = inboxStore.selectedThreadID else { return }
          let ordered = inboxStore.threads // already sorted desc by lastMessageAt
          guard let idx = ordered.firstIndex(where: { $0.id == active }) else { return }
          let nextIdx: Int
          switch direction {
          case .newer: nextIdx = (idx - 1 + ordered.count) % ordered.count  // wrap
          case .older: nextIdx = (idx + 1) % ordered.count
          }
          inboxStore.selectedThreadID = ordered[nextIdx].id
      }
      ```
      `J` → newer (= up in the list), `K` → older (= down). Note:
      Gmail wires it the other way (`J` older, `K` newer). Pick
      Gmail's mapping since users coming from Gmail outnumber the
      vim-purists; document in the help overlay.
- [x] **Wrap-around feedback**: when the cursor wraps from top
      back to bottom (or vice versa), pulse a 1-frame
      `rbAccent` border around the threadlist (use
      `withAnimation(.easeOut(duration: 0.18))` on a state flag).
- [x] **`Space` page-down-then-next-unread**: in `ThreadView`, wrap
      the message scroll content in a `ScrollViewReader`. Track
      `scrollPosition` via `.onScrollGeometryChange`. On `Space`:
      - If `scrollPosition.bottom > visibleBottom + 24pt`,
        scroll down by `visibleHeight * 0.85`.
      - Else find the next thread with `hasUnread == true` in
        `inboxStore.threads` after the current position; if found,
        switch to it. If not, show toast "No more unread mail."
- [x] Tests in `ThreadNavigationTests.swift` for J/K wrap and
      Space progression with mock threads (no AppKit needed for
      the logic part).

### Task 5: Folder jumps — `⌘1/2/3/4/5`

- [x] In `KeyboardDispatcher`:
      ```swift
      case folderInbox: sidebarSelection = .folder(.inbox)
      case folderStarred: sidebarSelection = .folder(.starred)
      case folderSent: sidebarSelection = .folder(.sent)
      case folderArchive: sidebarSelection = .folder(.archive)
      case folderAll: sidebarSelection = .allAccountsAllFolders
      ```
- [x] Wire `⌘1..⌘5` via `ShortcutSpec`. These are `modifiers: [.command]`
      so SwiftUI's native `.keyboardShortcut` handles them — no
      AppKit monitor needed.
- [x] Visual feedback: when the keyboard switches folders, briefly
      highlight the destination row in `RBSidebar` (200ms `rbAccentSoft`
      pulse).

### Task 6: Search focus — `⌘L`

- [x] In `RBToolbar.swift` search field, add `@FocusState` binding
      `searchFocused`. `⌘L` from `KeyboardDispatcher` flips it to
      `true`. `Esc` while focused flips back to `false`.
- [x] `Esc` also clears the search input if it had focus AND was
      non-empty (first Esc clears, second blurs).

### Task 7: `⌘⏎` Send in composer

- [x] In `ComposeWindowView.swift`:
      - Add `.keyboardShortcut(.return, modifiers: [.command])` to
        the Send button.
      - Same in `InlineComposer.swift` for its Send button.
      - Tooltip on Send: "Send (⌘⏎)".
- [x] If the send button is disabled (no body, no recipient),
      `⌘⏎` is a no-op (don't show a beep).

### Task 8: `?` keyboard-shortcut help overlay

- [x] Create `Apps/MacApp/Sources/Views/KeyboardHelpOverlay.swift`:
      a centered modal sheet listing `ShortcutSpec.all` grouped by
      `KeyboardSection`, each entry rendered as
      `[key combo] · description`.
- [x] Mount it in `MainScene` as a `.sheet(isPresented: $showHelp)`.
- [x] Bind `?` (Shift+/) to toggle. Also bind via the **Help menu**:
      Help → Keyboard Shortcuts (`⌘?` as the menu accelerator).
- [x] Style: monospace font for key combos, soft dividers between
      sections, fixed-width 480pt, dismissible by `?` again, `Esc`,
      or clicking outside.

### Task 9: Settings → Keyboard reference tab

- [x] New tab in `SettingsScene`, after AI: **Keyboard**.
- [x] Reuses the same grouped-list rendering as the help overlay
      (factor `KeyboardCatalogList` into a shared view).
- [x] Footer note: "Customisable shortcuts coming in a future
      release. Open an issue to request specific bindings."

### Task 10: Help menu wiring

- [x] In `PrivateAIMailApp.swift`'s `Commands`, add a
      `CommandGroup(replacing: .help)` containing a single
      "Keyboard Shortcuts" item with `.keyboardShortcut("?", modifiers: [.command, .shift])`
      → opens the help overlay.
- [x] Remove `CommandGroup(after: .toolbar)` (the current Refresh
      menu item) and re-add it under a new `CommandMenu("Mail")`
      with proper organisation: View / Mail / Compose / Help
      groupings matching the `KeyboardSection` enum.

---

## Cross-cutting tasks

- [ ] Bump `MARKETING_VERSION` to `0.1.9-alpha`,
      `CURRENT_PROJECT_VERSION` to `109`.
- [ ] Write `release-notes/v0.1.9-alpha.md`:
      - Reply / Reply All / Forward / Archive / Star / Trash /
        thread-nav / folder-jump / Send shortcuts now match Apple
        Mail + Gmail conventions.
      - `?` opens the full reference.
      - `⌘R` is now Reply (was Refresh — refresh moved to `F5` /
        `⌘⇧L`).
      - Single-letter shortcuts (`R`/`E`/`S`/`J`/`K`) only fire
        when no text field is focused.
- [ ] Update `EMAIL_ALF/14_macos_app_design.md` §15: mark step 13
      ✅, copy plan to `plans/fresh/completed/`.
- [ ] Add to `NOTES.md` under "Keyboard": a one-line summary of
      the catalog location (`Apps/MacApp/Sources/Keyboard/`).

## Critical files to read or modify

| Purpose | Path |
|---|---|
| Existing shortcut bindings | `Apps/MacApp/Sources/PrivateAIMailApp.swift:49-70`, `Apps/MacApp/Sources/Scenes/MainScene.swift:194-208` |
| Custom shortcut modifier | `Apps/MacApp/Sources/Scenes/MainScene.swift:321-326` |
| Toolbar search field | `Apps/MacApp/Sources/Views/RBToolbar.swift` (search for `SearchField`) |
| Composer Send button (full) | `Packages/Features/ComposeFeature/Sources/ComposeFeature/ComposeWindowView.swift` |
| Composer Send button (inline) | `Packages/Features/ComposeFeature/Sources/ComposeFeature/InlineComposer.swift` |
| Action Sheet dismiss | `Packages/Features/ActionsFeature/Sources/ActionsFeature/ActionSheetView.swift:199` |
| Mutations entry-points | `Apps/MacApp/Sources/Scenes/MainSceneMutations.swift` |
| Sidebar selection | `Apps/MacApp/Sources/Views/RBSidebar.swift` + `MainScene.sidebarSelection` |

## Existing functions and utilities to reuse (do not rewrite)

- `MailMutator.archive/star/trash/markRead` — Step 10 actions.
- `composition.replyStore.generateIfNeeded(...)` — Step 12 Reply
  path.
- `ComposeViewModel` — extend with `prefillForward(thread:)` and
  `prefillReplyAll(thread:)`.
- `inboxStore.selectedThreadID` + `inboxStore.threads` — J/K nav.
- `SidebarSelection` + `MainScene.sidebarSelection` binding — folder
  jumps.
- `composition.toastMessage` — feedback toasts.
- `ShowHelp` env mechanism (if any) — otherwise just a `@State` flag
  in MainScene.

## Verification (end-to-end smoke flow)

After Task 1–10 land:

```bash
cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
tuist generate --no-open
xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
open ~/Library/Developer/Xcode/DerivedData/PrivateAIMail-*/Build/Products/Release/PrivateAIMail.app
```

On `hlexxx@gmail.com`:

1. Press `?` → help overlay listing every shortcut. Press `?`
   again → dismisses.
2. Press `⌘R` on any thread → inline composer scrolls into view,
   AI draft generated. Press `R` (no modifier) on a thread row →
   same thing.
3. Press `R` while typing in the composer body → letter `R` is
   typed, no Reply triggered.
4. Press `⌘1` → jumps to Inbox. `⌘2` → Starred. `⌘3` → Sent.
   `⌘4` → Archive. `⌘5` → All Accounts.
5. Press `J` / `K` on a thread → switches to newer / older
   thread. At end-of-list, wraps with a subtle border pulse.
6. Press `Space` in a long thread → pages down. At end of
   message, second `Space` jumps to next unread thread.
7. Press `⌘L` → search field gets focus. Type `hilton` → press
   `Esc` → input clears. Press `Esc` again → search blurs.
8. Press `E` on a thread → archived, toast "Archived (Undo)".
9. Press `S` → star toggles, icon updates.
10. Press `#` → moved to trash. Press `⌘Z` → restored (toast
    Undo).
11. In compose window, press `⌘⏎` → sends.
12. Press `F5` → incremental sync runs (toast "Synced").
13. `xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme
    MacApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
    exits `** TEST SUCCEEDED **`.
14. `swiftlint --strict` reports zero violations.

## Non-regression contract

- Existing `⌘N` (compose), `⌘K` (action sheet), `⌘⇧R` (alias to
  Reply All), `⌘⇧R` previously-Draft-Reply path → still opens
  inline composer with AI draft.
- Esc closing the action sheet still works.
- Typing into ANY TextField/TextEditor — composer body, To/Cc
  fields, search — letters `R/A/F/E/S/J/K/?` produce letters,
  NOT trigger actions.
- All step 10–12 features remain functional.

## Out of scope for Step 13 (defer)

- **Customisable shortcuts** — Settings → Keyboard is read-only
  reference; remap UI is a future iteration.
- **Two-key sequences** (`gg`, `gi`, `gs` Gmail-style) —
  complex state machine; defer.
- **Vim mode toggle** — out of MVP scope.
- **Application-wide menu commands** beyond Mail / Help — toolbar
  menus stay default.
- **Per-window shortcuts** (compose window has different bindings
  than main window) — keep one global set; per-window
  customisation is future.
- **Right-click context menu** with shortcut hints — out of scope.
