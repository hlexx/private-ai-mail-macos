# Step 12 — Translation preserves HTML, real CTAs, broader Inbox backfill, layout breath

## Overview

After shipping v0.1.7-alpha, the user smoke-tested on a real Gmail inbox
and surfaced five issues that the previous iterations didn't catch:

1. **Translation tab destroys HTML layout.** Russian translation of a
   marketing email rendered as a wall of plain text that included CSS
   rule names ("Семейство шрифтов: Arial, Helvetica, sans-serif!
   Важный;", "Mso-line-height-rule: точно;"). Style blocks bled into
   the plaintext extraction AND the translated-rendering path strips
   all HTML structure.
2. **All Accounts filter shows only 1 thread**, even after M008
   backfill. M008 only inserts INBOX for threads with **zero**
   thread_label rows; most legacy threads have OTHER labels (UNREAD,
   CATEGORY_PROMOTIONS) but never had INBOX → still excluded.
3. **Translation engine confusion.** User asked "is translation via
   Gemma?" — release notes never spelled out that translation uses
   Apple's `Translation` framework, on-device, separate from the
   Gemma LLM. Worth a clarification in user-facing copy.
4. **Brief-rail CTAs are dead.** "Draft reply", "Snooze to Fri AM",
   "Log to CRM" — three buttons in BriefRail.swift:120-145 all have
   empty action closures. Clicking them does nothing.
5. **Reading + brief pane is too narrow.** 240px sidebar + 360px
   threadlist + 340px brief rail = on a 1440px window, the reading
   pane gets ~500px. HTML email + AI brief are the most valuable
   surfaces but get the least real estate.

Step 12 closes all five.

## Context (verified 2026-05-18 against `main` at `c0cb664`)

### What's broken

- **`MessageBodyView.htmlToPlainText`
  (Packages/Features/ThreadFeature/Sources/ThreadFeature/MessageBodyView.swift:82)**
  — uses `NSAttributedString(data: html, options: [.documentType: .html])`.
  When the email has top-level `<style>...</style>` blocks (very
  common in marketing mail), this parser sometimes includes the CSS
  rule text in `attributed.string`. The Translation pipeline then
  feeds Apple's translator strings like
  `"body, table, td {font-family: Arial...! important;}"` and the
  translator translates *the CSS keywords* too. Result: CSS in
  Russian, broken layout.
- **`ThreadView.swift:276-281`** — when `translatedText != nil`, the
  message card renders `Text(translated)` (plain SwiftUI Text). The
  whole HTML structure of the original message is gone — no images,
  no tables, no lists, no quotes. Even a clean translation looks
  like a wall of paragraphs.
- **`Persistence/Migrator.swift` M008** — backfill SQL:
  ```sql
  WHERE NOT EXISTS (SELECT 1 FROM thread_label tl
                    WHERE tl.account_id = t.account_id
                      AND tl.thread_id = t.id)
  ```
  Threads that received ANY label row during incremental sync
  (UNREAD, IMPORTANT, CATEGORY_PROMOTIONS, etc.) are excluded from
  the backfill, even if they're missing INBOX specifically. User's
  hlexxx@gmail.com showed 475 threads under "hlexxx@gmail.com"
  account but only 1 under "All Accounts" → ~474 threads have some
  label, but not INBOX.
- **`BriefRail.swift:120-145`** — three CTAs (`Draft reply` →
  empty `{}`, `Snooze to Fri AM` → empty `{}`, `Log to CRM` →
  empty `{}`). No view-model surface to hook them into; the brief
  rail receives only `briefStore: BriefStore` but no callback API
  for actions.
- **Layout constants** (search for `RBLayout.briefRailWidth`,
  `sidebarWidth`, `threadlistWidth` in `RBLayout.swift` if it
  exists, or hardcoded `.frame(width: 240)` / `.frame(width: 360)`
  / `.frame(width: 340)` in `MainScene.swift` and `BriefFeature` /
  `InboxFeature`). All three sizes are non-resizable, non-collapsible.
- **Release notes (v0.1.5 + v0.1.6 + v0.1.7)** — never mention that
  translation is via Apple Translation. Users could reasonably
  assume the on-device AI does it.

### What's already there (reuse)

- `WKWebView` host in `MessageBodyView.HTMLWebView` already renders
  the email's HTML with CSP. JS injection (`evaluateJavaScript`) is
  available; we can walk the DOM after load.
- `TranslationSession.translate(_:)` accepts a plain string and
  returns a translated string. It can also accept a sequence
  (`translate(batch:)`) for batched throughput.
- `BriefStore` already exposes the active brief; can carry an
  `onDraftReply` callback or expose imperative `requestDraftReply()`
  via the existing observable surface.
- `InlineComposer` is already mounted in the reading-pane column;
  scrolling/focusing it is a matter of `ScrollViewReader` +
  `proxy.scrollTo(...)`. Or expose a focus-binding from
  `ComposeViewModel`.
- `RBLayout` constants live in DesignSystem (find via grep). Add a
  `@AppStorage` overrideable per-pane width if missing.
- `MailMutator.snooze(...)` doesn't exist yet (Snooze was Phase 2).
  Step 12 either wires Snooze as best-effort (label "Snoozed-Fri"
  + remove INBOX, restore via background timer) OR drops the
  button to a Phase 2 stub with an explicit `.disabled(true)` and
  tooltip "Coming in Phase 2".

## Success Criteria

Verified on `hlexxx@gmail.com` (475 threads, multilingual, HTML-heavy):

1. **All Accounts shows every Inbox thread.** M009 backfills INBOX
   for any thread that does NOT explicitly carry TRASH/SPAM/DRAFT
   and is missing INBOX. After upgrade + first launch, "All
   Accounts" matches per-account count (≥ 470 threads).
2. **Translated tab preserves HTML.** Open a Russian marketing
   email (Сколково / Vacandi). Click **Translated**. The layout
   (header image, CTA buttons, font sizes, table cells) survives;
   only the text inside `<p>`, `<h*>`, `<td>`, `<li>`, etc. nodes
   shows in English. CSS rule text never appears. No "Семейство
   шрифтов" leakage.
3. **AI brief no longer parrots CSS.** For HTML-heavy promotional
   emails, the brief reads about the actual message ("Hilton 20%
   summer sale", not "Body table td font-family Arial").
4. **Draft Reply button drafts a reply.** Click "Draft reply" in
   the brief rail → reading-pane scrolls to the inline composer,
   composer is focused, AI generates a draft in the thread's
   language with the default tone. Same flow if user uses
   `⌘shift+R` keyboard shortcut.
5. **Snooze + Log to CRM either work or are gracefully Phase-2'd.**
   Snooze: clicking adds a `Snoozed` label (or `Snoozed-Fri-AM`)
   in Gmail and removes INBOX (thread vanishes from inbox, lands
   back next Friday — best-effort, no background scheduler yet —
   document as alpha behavior). Log to CRM: explicitly disabled
   with a tooltip "Phase 2 — connect Notion/HubSpot/Salesforce
   first". User isn't surprised by inert buttons.
6. **Reading + brief pane gets ~60-70% of window width on a 1440px
   window.** Sidebar collapses to icon-only (48px) with a toggle
   in the toolbar; threadlist has a resizable splitter; brief
   rail has its own collapse-to-72px state with a chevron. New
   defaults on first launch:
   - 1440px window: sidebar 200, threadlist 320, reading 580,
     brief 340 → reading + brief = 64% of window.
   - 1920px window: sidebar 240, threadlist 360, reading 980,
     brief 340 → reading + brief = 69%.
   - Splitters are draggable; positions persist in `@AppStorage`.
7. **Release notes for v0.1.8-alpha clarify** that translation is
   via Apple's `Translation` framework (on-device, no network,
   independent of the Gemma LLM brief/draft-reply pipeline).

## Validation Commands

```bash
PROJ=/Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
cd $PROJ && tuist generate --no-open
cd $PROJ && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
cd $PROJ && swiftlint --strict
cd $PROJ/Packages/Core/Persistence && swift test
cd $PROJ/Packages/Features/ThreadFeature && swift test
cd $PROJ/Packages/Features/TranslationFeature && swift test
cd $PROJ/Packages/Features/BriefFeature && swift test
cd $PROJ/Packages/Features/InboxFeature && swift test
cd $PROJ/Packages/Features/ComposeFeature && swift test
cd $PROJ/Packages/Mail/MailSync && swift test
cd $PROJ && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build
```

---

### Task 1: M009 — broader INBOX backfill

Re-run backfill to catch threads that have SOME labels but not INBOX.

- [x] Add `M009_BackfillInboxLabelV2` in `Migrator.swift`. SQL:
      ```swift
      enum M009_BackfillInboxLabelV2 {
          static func migrate(_ db: Database) throws {
              // Same INSERT OR IGNORE for the canonical INBOX system label
              // per account (idempotent with M008).
              try db.execute(sql: """
                  INSERT OR IGNORE INTO label (id, account_id, name, type, color, messages_unread_count, messages_total_count)
                  SELECT 'INBOX', a.id, 'Inbox', 'system', NULL, 0, 0
                  FROM account a
                  """)
              // Insert INBOX row for any thread that:
              // - does NOT already have an INBOX label row, AND
              // - does NOT have any of TRASH/SPAM/DRAFT (i.e. is not
              //   explicitly out-of-inbox)
              // - is NOT exclusively SENT-only (sent-mail-to-others is
              //   shown only under Sent, not Inbox)
              try db.execute(sql: """
                  INSERT OR IGNORE INTO thread_label (account_id, thread_id, label_id)
                  SELECT t.account_id, t.id, 'INBOX'
                  FROM thread t
                  WHERE NOT EXISTS (
                      SELECT 1 FROM thread_label tl_in
                      WHERE tl_in.account_id = t.account_id
                        AND tl_in.thread_id = t.id
                        AND tl_in.label_id = 'INBOX'
                  )
                  AND NOT EXISTS (
                      SELECT 1 FROM thread_label tl_out
                      WHERE tl_out.account_id = t.account_id
                        AND tl_out.thread_id = t.id
                        AND tl_out.label_id IN ('TRASH','SPAM','DRAFT')
                  )
                  AND NOT (
                      EXISTS (SELECT 1 FROM thread_label tl_sent
                              WHERE tl_sent.account_id = t.account_id
                                AND tl_sent.thread_id = t.id
                                AND tl_sent.label_id = 'SENT')
                      AND NOT EXISTS (SELECT 1 FROM thread_label tl_any
                                      WHERE tl_any.account_id = t.account_id
                                        AND tl_any.thread_id = t.id
                                        AND tl_any.label_id NOT IN ('SENT','UNREAD','IMPORTANT'))
                  )
                  """)
          }
      }
      ```
- [x] Register in the migration list AFTER M008.
- [x] Tests in `PersistenceTests/LabelBackfillV2Tests.swift`:
      - Seed thread A with no labels → M009 inserts INBOX.
      - Seed thread B with `CATEGORY_PROMOTIONS` only → M009 inserts
        INBOX.
      - Seed thread C with `TRASH` → M009 does NOT insert INBOX.
      - Seed thread D with `SENT` only → M009 does NOT insert INBOX
        (sent-only).
      - Seed thread E with `SENT` + `UNREAD` + `CATEGORY_FORUMS`
        (sent to a mailing list) → M009 inserts INBOX (mixed).
      - Re-run M009 → no duplicate INBOX rows (idempotent).
- [x] Run `cd $PROJ/Packages/Core/Persistence && swift test`.

### Task 2: Strip `<style>` and `<script>` before plaintext extraction

Stop CSS bleeding into AI input + Translation input.

- [x] In `MessageBodyView.htmlToPlainText` (line 82): before passing
      to `NSAttributedString(html:)`, strip `<style>...</style>` and
      `<script>...</script>` blocks (case-insensitive, multi-line).
      Simplest: a regex pre-pass.
      ```swift
      let stripped = html
          .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>",
                                with: "",
                                options: [.regularExpression, .caseInsensitive])
          .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>",
                                with: "",
                                options: [.regularExpression, .caseInsensitive])
      ```
      Then proceed with NSAttributedString on `stripped`.
- [x] Apply same strip in `MessageRecord.htmlToPlainText`
      (Packages/Core/Persistence/.../MessageRecord.swift:69) — that's
      the path AI brief + ReplyStore use. Keep the two implementations
      in sync; ideally factor into one helper exported from
      `Persistence` and reused by both.
- [x] Tests: a fixture HTML email containing a `<style>` block with
      CSS rules → assert plainText does NOT contain `font-family`
      and IS just the body text.
- [x] Run `cd $PROJ/Packages/Features/ThreadFeature && swift test`
      and `cd $PROJ/Packages/Core/Persistence && swift test`.

### Task 3: Translation preserves HTML — DOM walk in WKWebView

Translate text nodes only; keep CSS, layout, images, links intact.

**Architecture (read carefully — important details):**

The flow is **single WKWebView, dual DOM state**:
1. WebView loads the original HTML (already happens today).
2. On `webView(_:didFinish:)`, Swift injects a small extraction JS via
   `evaluateJavaScript`. The JS walks the DOM with `TreeWalker(SHOW_TEXT)`,
   assigns each non-whitespace text node a sequential dataset id by
   wrapping it in a `<span data-tx-id="n0">…</span>` (or stamping the
   parent), and returns the array `[{id, text}]` via a single
   `evaluateJavaScript` return value.
3. Swift receives `[(id, text)]`, batch-translates via
   `TranslationSession.translate(_ requests:)` (the batched API
   accepts `[TranslationSession.Request]` and returns
   `AsyncSequence<TranslationSession.Response>`). Results cached in
   `TranslationStore.translatedNodes[messageId][nodeId]`.
4. When user clicks **Translated** segment: Swift calls
   `evaluateJavaScript` again with an apply-script that takes the
   `{n0: "Hello", …}` map and replaces each `[data-tx-id="…"]`
   node's `textContent`. Switching back to **Original** runs another
   apply-script that restores the original text from a `data-tx-orig`
   attribute set during extraction.
5. **No WKScriptMessageHandler needed.** All communication is via
   `evaluateJavaScript`'s reply value (which can return JSON-serialisable
   arrays/dicts). Simpler, no leak/retain dance, no CSP allowance.

**CSP note.** Our existing CSP for `HTMLWebView` (set via
`<meta http-equiv="Content-Security-Policy">` in the loaded HTML)
must not block `evaluateJavaScript` (it doesn't — host-driven JS
bypasses CSP) but also must not require `script-src`. Keep current
CSP unchanged.

**bodyText-only fallback.** When `bodyHtml == nil` (plain text
email), there's no HTML structure to preserve. Render the translated
plain text inside a `Text(translated)` with `.lineSpacing(4)` (the
existing path on line 277). Do NOT inject any JS in this branch —
no WebView is mounted for text-only emails.

**Cache invalidation.**
- Cache key: `(messageId, targetLanguageBCP47)`.
- Invalidate when: `Settings.preferredLanguage` changes, OR
  `MessageRecord.bodyHtml` / `bodyText` changes (new sync brought
  edits — `translatedNodes[messageId]` is dropped). Listen to
  `Settings.preferredLanguage` via `@AppStorage` change observer in
  `TranslationStore`.
- Persistence is in-memory only for this iteration (Step 10's
  `MessageRecord.translatedText` column remains unused for now —
  per-node map persistence is a Phase 2 follow-up, document it).

**Performance.**
- Use the batched API. Translating N text nodes with N separate
  `session.translate(_:)` calls serialises N XPC round-trips. The
  batched form yields all responses concurrently.
- Cap node-extraction at 2000 text nodes per message (>2k is almost
  certainly a degenerate HTML email — anything more and we render a
  "Translation truncated; some text may remain in the original
  language" banner above the body).
- Whitespace-only text nodes are skipped before extraction —
  reduces N by ~50% on typical marketing HTML (text nodes between
  `<td>` and `<p>` tags are mostly whitespace).
- HTML entities (`&nbsp;`, `&amp;`, etc.) — the TreeWalker returns
  decoded text content, so entities are auto-resolved before
  translation. Re-encoding on apply isn't needed because
  `textContent =` setter HTML-escapes automatically.

**Tasks:**

- [x] Extend `HTMLWebView` (`MessageBodyView.swift`) with:
      - New init parameter `translatedNodes: [String: String]?`
        (default `nil`). When `nil` → render original. When non-nil
        → render with translations applied.
      - Inject extraction script in `webView(_:didFinish:)` if
        `onTextNodesExtracted` callback closure is set. This
        callback hands back `[(id: String, text: String)]` to the
        parent view.
      - Wrap-and-tag JS:
        ```js
        (function () {
          const out = [];
          const w = document.createTreeWalker(
              document.body, NodeFilter.SHOW_TEXT,
              { acceptNode: n =>
                  n.parentNode &&
                  !['SCRIPT','STYLE','NOSCRIPT'].includes(n.parentNode.nodeName) &&
                  n.nodeValue.trim().length > 0
                      ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT
              }
          );
          let i = 0;
          while (w.nextNode()) {
              const span = document.createElement('span');
              span.dataset.txId = 'n' + i;
              span.dataset.txOrig = w.currentNode.nodeValue;
              span.textContent = w.currentNode.nodeValue;
              w.currentNode.parentNode.replaceChild(span, w.currentNode);
              out.push({id: 'n' + i, text: w.currentNode ? w.currentNode.nodeValue : span.textContent});
              i++;
              if (i >= 2000) break;
          }
          return JSON.stringify(out);
        })();
        ```
      - Apply-translations JS:
        ```js
        (function (map) {
          for (const span of document.querySelectorAll('[data-tx-id]')) {
              const id = span.dataset.txId;
              if (map[id] !== undefined) span.textContent = map[id];
          }
        })(__MAP__);
        ```
        (substitute `__MAP__` with the JSON-encoded translation map
        before injection).
      - Restore-original JS:
        ```js
        (function () {
          for (const span of document.querySelectorAll('[data-tx-id]')) {
              span.textContent = span.dataset.txOrig;
          }
        })();
        ```
- [x] Refactor `TranslationStore`:
      - Replace `translatedTexts: [messageId: String]` with
        `translatedNodes: [messageId: [String: String]]`.
      - New method `applyTranslations(messageId:, nodes:[(id, text)], source:, target:) async`
        that batch-translates and stores the result map.
      - Keep `setTranslating`/`setError`/`showTranslated` flags from
        v0.1.6 implementation.
      - Listen for `Settings.preferredLanguage` change via
        `@AppStorage` Combine publisher (or `NotificationCenter`),
        wipe `translatedNodes` on change.
- [x] In `ThreadView.MessageCardView` (line 276):
      ```swift
      if showTranslated, let bodyHtml = message.bodyHtml {
          MessageBodyView(
              bodyHtml: bodyHtml,
              bodyText: message.bodyText,
              snippet: message.snippet,
              attachments: ...,
              translatedNodes: translationStore.translatedNodes[message.id]
          )
      } else if showTranslated, let translated = translatedText {
          // bodyText-only fallback
          Text(translated)
              .font(.rbGeist(14))
              .foregroundStyle(Color.rbFg2)
              .lineSpacing(4)
              .textSelection(.enabled)
      } else {
          MessageBodyView(bodyHtml: message.bodyHtml, ...)  // original
      }
      ```
- [x] Wire extraction → translation in `TranslationView` /
      `TranslationStore`: when user clicks **Translated** AND a
      message has `bodyHtml != nil`, the `MessageBodyView` returns
      its extracted nodes via the new callback; the store batch-
      translates; result cached; toggle re-renders with
      `translatedNodes` non-nil.
- [x] Edge case: re-extraction race. If the user clicks
      Translated → Original → Translated rapidly, ensure only the
      latest extraction's translation is applied. Use a token /
      generation counter per (messageId, languagePair).
- [x] Tests in `TranslationFeatureTests`:
      - Fixture HTML with `<h1>Hello</h1><p>World</p>` + a
        `<style>` block → after extraction, expect exactly 2 text
        nodes (`"Hello"`, `"World"`), zero style content leakage.
      - Apply translation map `{n0: "Привет", n1: "Мир"}` →
        resulting HTML still contains `<h1>` and `<p>` with
        translated text.
- [x] Tests in `ThreadFeatureTests`: snapshot of `MessageCardView`
      with translated HTML email shows preserved layout (use a
      fixture HTML with a colored `<h1>` — the color must survive).
- [x] Run `cd $PROJ/Packages/Features/TranslationFeature && swift test`
      and `cd $PROJ/Packages/Features/ThreadFeature && swift test`.

### Task 4: Wire Brief Rail CTAs

Only **Draft Reply** ships wired in this iteration. Snooze and Log
to CRM stay as explicit disabled-with-tooltip — wiring them without
a real scheduler / CRM integration would surprise the user (Snooze
without auto-restore is just hidden mail; CRM without an integration
is a nothing-burger).

- [x] Extend `BriefRail` view to take callback `onDraftReply: (() -> Void)?`
      (default `nil`). The other two buttons get `.disabled(true)` +
      `.help(...)` tooltips, no callbacks.
- [x] Add an `anchor` enum + named `id` for the inline composer in
      `ThreadView`:
      ```swift
      enum ThreadViewAnchor: Hashable { case head, composer }
      ```
      Wrap the entire reading-pane content in a `ScrollViewReader`
      (it's already inside a `ScrollView` per step 10). Tag the
      `InlineComposer` view with `.id(ThreadViewAnchor.composer)`.
- [x] Wire `MainScene` to:
      ```swift
      BriefRail(
          store: briefStore,
          onDraftReply: {
              withAnimation { scrollProxy.scrollTo(ThreadViewAnchor.composer, anchor: .top) }
              composerFocus.wrappedValue = .body
              // If no draft has been generated yet for this (thread, tone, lang) tuple,
              // kick one off. If already cached, just scroll+focus.
              Task { await replyStore.generateIfNeeded(
                  threadId: activeThreadId,
                  accountId: activeAccountId,
                  tone: composeViewModel.tone,
                  replyLanguage: detectThreadLanguage()
              ) }
          }
      )
      ```
      Where `composerFocus` is a `@FocusState<InlineComposer.Focus?>`
      bound through to InlineComposer (extend InlineComposer to
      expose a `focus` binding with cases `.body`, `.subject`, etc).
- [x] **Snooze** button: `.disabled(true)` with `.help("Coming in
      Phase 2 — needs an in-app scheduler")`. Visually keep the
      sf-symbol clock + label so layout doesn't shift.
- [x] **Log to CRM** button: `.disabled(true)` with `.help("Coming
      in Phase 2 — connect a CRM in Settings → Integrations
      first.")` Same visual.
- [x] Keyboard shortcut `⌘⇧R` triggers `onDraftReply` from anywhere
      in MainWindow. Add a `Commands` block in
      `PrivateAIMailApp.swift` to register it (look for the existing
      `⌘N` compose shortcut for the pattern).
- [x] Update `ReplyStore` if `generateIfNeeded(...)` doesn't exist:
      add it as a thin wrapper that checks the cache (Step 11's
      brief-cache pattern in `BriefStore`) and only calls
      `aiService.draftReply(...)` on miss.
- [x] Tests for `BriefRail`:
      - Snapshot with `onDraftReply` non-nil — Draft button is
        enabled.
      - Snapshot with `onDraftReply == nil` — Draft button is
        disabled too (preview / test affordance).
      - Snooze + Log to CRM always disabled, tooltips assertable.
- [x] Tests for the keyboard shortcut: a small AppKit-level test
      that simulates `⌘⇧R` and asserts the binding is set.
- [x] Run `cd $PROJ/Packages/Features/BriefFeature && swift test`
      and `cd $PROJ/Packages/Features/ComposeFeature && swift test`.

### Task 5: Layout — collapsible panes + reading-first defaults

**Implementation note.** SwiftUI's `HSplitView` is too primitive — it
doesn't expose drag-end events so we can't persist runtime drag
positions via `@AppStorage`. Use **`NSSplitViewController` wrapped in
`NSViewControllerRepresentable`** to:
- get drag-end via `splitViewDidResizeSubviews(_:)` delegate method
- set per-pane `holdingPriority` to control which pane resists
  resizing when the window grows
- support `collapseBehavior: .preferResizingSplitViewWithFixedSiblings`
  for clean collapse/expand without rearranging other panes
- persist position via `setAutosaveName("pam.mainSplit")` (NSSplitView
  has built-in autosave; complements but doesn't replace `@AppStorage`
  which we use for the initial defaults and the collapsed/expanded
  bool flags)

**Reading-pane budget targets:**
| Window | Sidebar | Threadlist | Reading | Brief | Reading+Brief % |
|---|---|---|---|---|---|
| 1280 | 180 | 280 | 540 | 280 | **64%** |
| 1440 | 200 | 320 | 580 | 340 | **64%** |
| 1920 | 240 | 360 | 980 | 340 | **69%** |

**Tasks:**

- [ ] Replace the current layout in `MainScene.swift` with an
      `NSSplitViewController` bridge. Create
      `Apps/MacApp/Sources/Views/MainSplitController.swift`:
      ```swift
      struct MainSplitController: NSViewControllerRepresentable {
          @Binding var sidebarCollapsed: Bool
          @Binding var briefCollapsed: Bool
          @AppStorage("pam.layout.sidebar") private var sidebarWidth: Double = 240
          @AppStorage("pam.layout.threadlist") private var threadlistWidth: Double = 320
          @AppStorage("pam.layout.brief") private var briefWidth: Double = 340
          let sidebar: () -> AnyView
          let threadlist: () -> AnyView
          let reading: () -> AnyView
          let brief: () -> AnyView
          // makeNSViewController → NSSplitViewController with 4 NSSplitViewItem,
          // each wrapping NSHostingController(rootView: AnyView)
          // updateNSViewController → toggles `isCollapsed` on items 0 and 3
          //                          and writes back widths from delegate
      }
      ```
- [ ] Each `NSSplitViewItem` configured:
      - **Sidebar item (index 0)**: `minimumThickness = 180`,
        `maximumThickness = 320`, `canCollapse = true`,
        `collapseBehavior = .preferResizingSplitViewWithFixedSiblings`,
        `holdingPriority = .defaultLow + 1` (resists window resize
        less than middle panes).
      - **Threadlist (index 1)**: `minimumThickness = 280`,
        `maximumThickness = 480`, `canCollapse = false`.
      - **Reading (index 2)**: `minimumThickness = 480`,
        `holdingPriority = .defaultLow` (flexes to fill).
      - **Brief (index 3)**: `minimumThickness = 280`,
        `maximumThickness = 420`, `canCollapse = true`,
        `holdingPriority = .defaultLow + 1`.
- [ ] Wire `sidebarCollapsed` + `briefCollapsed` `@State` bindings in
      `MainScene.swift`. Defaults read from `@AppStorage` bool flags
      `pam.layout.sidebarCollapsed` and `pam.layout.briefCollapsed`.
      When user toggles, write back.
- [ ] **Toolbar item — Sidebar toggle.** Add to `RBToolbar.swift`:
      `RBIconButton(systemImage: "sidebar.leading")` that flips
      `sidebarCollapsed`. Position: leading group, before the
      account switcher.
- [ ] **Brief-rail collapse chevron.** When `briefCollapsed == false`,
      `BriefRail` shows a `chevron.right` button in its top-right
      corner. When `briefCollapsed == true`, the split-view item
      collapses to 0pt — there's no thin strip to click on (SwiftUI's
      collapse is binary). To re-open, add a **toolbar item**
      `RBIconButton(systemImage: "sidebar.trailing")` mirroring the
      sidebar toggle. This is simpler and matches macOS Mail behavior.
- [ ] Persistence: `splitViewDidResizeSubviews(_:)` delegate writes
      live widths into the `@AppStorage` bindings. On view reappear,
      `updateNSViewController` reads stored widths and sets each
      item's `preferredHoldingPriority` so the splitter snaps to
      them.
- [ ] Window minimum size: 980×720pt (allows the 280+280+340 minimum
      pane widths to coexist). Set in `PrivateAIMailApp.swift`'s
      `WindowGroup` via `.defaultSize` + `.minSize` (or via the
      window introspection helper).
- [ ] Snapshot tests are hard for NSSplitViewController in a
      unit-test context; add a `MacAppTests` UI-test that opens the
      window, asserts default widths, drags a splitter, quits and
      reopens, asserts width persisted.
- [ ] Smoke-test manually on 1280/1440/1920 widths against the table
      above before merge.
- [ ] Run full validation gate.

### Task 6: Release notes + clarify Apple Translation

- [ ] Bump `MARKETING_VERSION` to `0.1.8-alpha`,
      `CURRENT_PROJECT_VERSION` to `108`.
- [ ] Write `release-notes/v0.1.8-alpha.md` covering: Inbox backfill
      catches more threads (M009), translation preserves HTML
      layout, Brief Rail buttons work, layout is responsive and
      reading-first, **explicit note** that translation uses
      Apple's on-device `Translation` framework (independent of
      Gemma — Gemma stays in charge of brief + reply drafts).
- [ ] Add a one-line "How it works" badge in Settings → AI tab:
      "Brief + Reply: Gemma 4 (on-device, MLX). Translation: Apple
      Translation framework (on-device)."
- [ ] Update `EMAIL_ALF/14_macos_app_design.md` §15: mark step 12 ✅
      with merge commit, copy plan to `plans/fresh/completed/`.

---

## Critical files to read or modify

| Purpose | Path |
|---|---|
| Inbox backfill broken | `Packages/Core/Persistence/Sources/Persistence/Migrator.swift` (after `M008_BackfillInboxLabel`) |
| Plaintext extraction includes CSS | `Packages/Features/ThreadFeature/Sources/ThreadFeature/MessageBodyView.swift:82` + `Packages/Core/Persistence/Sources/Persistence/Records/MessageRecord.swift:69` |
| Translated tab loses HTML | `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift:276-281` |
| Translation pipeline | `Packages/Features/TranslationFeature/Sources/TranslationFeature/TranslationView.swift:118-141` + `TranslationStore.swift` |
| Brief Rail CTAs dead | `Packages/Features/BriefFeature/Sources/BriefFeature/BriefRail.swift:120-145` |
| Layout (sidebar / threadlist / brief widths) | `Apps/MacApp/Sources/Scenes/MainScene.swift` + grep `briefRailWidth\|sidebarWidth\|threadlistWidth` |
| Composition root | `Apps/MacApp/Sources/CompositionRoot.swift` |
| Snooze via Mutator | `Packages/Mail/MailSync/Sources/MailSync/MailMutator.swift` (extend with `snooze(threadId:accountId:)`) |

## Existing functions and utilities to reuse (do not rewrite)

- `WKWebView` already in use for HTML rendering — same instance can
  host the DOM-walk JS injection.
- `TranslationSession.translate(_:)` and `translate(batch:)` —
  reuse for batched node translation.
- `MailMutator` actor pattern (Step 10 Task 6) — same shape for
  `snooze(threadId:)`.
- `@AppStorage` is already used in Settings — reuse for layout
  persistence.
- `ScrollViewReader` + named anchors — for scroll-to-composer.
- `FocusState` — for composer focus after Draft Reply.

## Verification (end-to-end smoke flow)

After Task 1-6 land:

```bash
cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
tuist generate --no-open
xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
open ~/Library/Developer/Xcode/DerivedData/PrivateAIMail-*/Build/Products/Release/PrivateAIMail.app
```

On `hlexxx@gmail.com`:

1. First launch after update: M009 runs once. All Accounts and
   Inbox both show 470+ threads.
2. Open a Сколково / Hilton marketing email → Translated tab →
   layout preserved (header banner, button styles, table cells),
   text in English. No "Семейство шрифтов" leakage.
3. Open a multi-paragraph email → AI brief reads about actual
   subject, not CSS rules.
4. Click **Draft reply** in Brief Rail → reading pane scrolls to
   inline composer, AI generates draft in thread's language. Type
   over it → Send works.
5. Click **Snooze to Fri AM** → thread vanishes from Inbox, lands
   in a "Snoozed" custom label visible in Gmail web UI. Manual
   unsnooze by re-adding INBOX.
6. **Log to CRM** is disabled with tooltip explaining Phase 2.
7. Drag the splitter between sidebar/threadlist → resizes
   smoothly. Quit + relaunch → width persists.
8. Click sidebar-collapse toolbar button → sidebar disappears,
   account switcher inflates. Click again → sidebar reappears.
9. Click brief-rail chevron → rail collapses to a thin strip with
   "Brief" label vertical. Click strip → re-expands.
10. Settings → AI tab → tooltip explains translation is via Apple
    Translation, brief + reply via Gemma 4 / MLX.

## Non-regression contract

Step 12 changes touch the most-trafficked surfaces of the app
(message rendering, translation, layout). Before merging the branch,
the following must still hold:

- Plain-text emails (no `bodyHtml`) render via SwiftUI `Text` —
  unchanged behavior.
- AI brief on a long English email reads about the content, not
  CSS keywords (this was the original step-10 contract — verify it
  still works AND now also works on emails with `<style>` blocks
  thanks to Task 2).
- Reply draft language detection still routes correctly (Step 10
  Task 8 — verify against a Russian thread).
- Sidebar filter clicks still scope by label (Step 10 Task 3 —
  verify Inbox / Sent / Starred / Archive after M009 backfill).
- `MailMutator.archive/star/trash/markRead` mutations still hit
  the Gmail API with the right add/remove pairs (Step 10 Task 6).
- The 130+ tests across packages stay green.

If any of the above regress, hold the merge and investigate.

## Post-merge user instructions to include in release notes

- After install, the first launch runs M009 once (a few seconds).
  All Accounts / Inbox should immediately show ~all your threads.
- Optionally hit `⌘R` to do an incremental sync — this overwrites
  the M009 backfilled `INBOX` rows with the real label set from
  Gmail (no-op for threads still in inbox, removes the backfill
  for threads Gmail actually archived since last sync).
- The Translated tab now preserves HTML layout. First click after
  upgrade re-runs translation against the new pipeline (cached
  translations from v0.1.7 are dropped).
- New keyboard shortcut: `⌘⇧R` opens the inline composer and
  drafts a reply for the active thread.
- Drag the splitters between sidebar / threadlist / reading /
  brief to resize. Toolbar icons toggle sidebar and brief
  collapse. Layout persists across quits.

## Out of scope for Step 12 (defer)

- Real Snooze scheduler — needs a background timer / launchd
  agent; deferred to Step 13.
- Log to CRM — Phase 2 / Integrations panel.
- Per-language persistent translation cache table (`message_translation`)
  — in-memory only for now.
- Iconified sidebar (collapse-to-icons mode) — full-collapse only.
- Per-thread "always translate" override — Phase 2.
- Translation language pair download UI — Apple's framework handles
  the prompt natively.
- Push notifications via broker — Phase 2.
- Outlook/Graph provider — Phase 2.
