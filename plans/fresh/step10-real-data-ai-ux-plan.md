# Step 10 — Real-data UX, label-aware filtering, multi-language AI, HTML rendering

## Overview

After v0.1.4-alpha shipped and the user ran the app against a real Gmail
inbox (`hlexxx@gmail.com`, 423 threads, mixed RU/EN, HTML-heavy
marketing mail), a smoke-test surfaced ten concrete UX/data gaps that
the earlier §15 steps marked as ✅ but only landed infrastructure for.
This plan closes the gap: schema for labels, HTML rendering, real AI in
the inline composer, label-aware filtering, mutations (archive / star /
move), translation tab, layout fixes, and language preference.

After Step 10, the app should be **usable as a daily Gmail client on
real data** — not a curated demo. See §15 in
`/Users/alexeykhaynovsky/Documents/Projects/EMAIL_ALF/14_macos_app_design.md`
for the corrected post-v0.1.4 status.

## Context (current code state — verified 2026-05-17)

Read this before touching anything — many things look done but aren't:

### What's real
- `Bootstrap.swift:85` calls `api.getThread(id:format:.full)` — we pull
  full MIME bodies.
- `GmailMapper.swift:19` parses both `text/plain` AND `text/html` parts
  into `bodyText` + `bodyHtml`.
- `MessageRecord.swift:19` persists `bodyHtml` to SQLite (`body_html`
  column).
- `AIService.threadBrief()` (Packages/AI/AIKit/Sources/AIKit/) does run
  Gemma on-device via MLX. `MLXThreadBriefService` exists and works.
- Full Compose-window send hits Gmail send API (Step 7 — verified).
- `BriefStore.swift:74` calls `aiService.threadBrief(input)` for real.

### What's stub / broken
- `ThreadView.swift:234` renders **only** `message.bodyText`,
  ignoring `bodyHtml`. HTML-only emails (most marketing mail, Russian
  promotions) show snippet only.
- `BriefStore.swift:126` feeds AI `msg.bodyText ?? msg.snippet ?? ""`
  — for HTML-only mail this collapses to snippet, AI hallucinates from
  5 words.
- `InlineComposer.swift:22-26` — **hardcoded English `draftBodies`
  dictionary**. Tone segments swap one of three preset paragraphs.
  Regenerate (line 127-129) re-assigns from the same dict.
  `AIService.draftReply()` does **not exist** in the AIKit protocol.
- `AIService.swift:3-5` exposes **only** `threadBrief`. Reply
  generation has zero protocol surface, zero MLX wiring.
- `RBSidebar.swift` — `FolderItem` rows render but the view takes no
  `onSelect`/`selection`-binding. Clicks do nothing.
  `MainScene.swift:143-150` computes `sidebarFolders` but never
  consumes any folder selection downstream.
- `InboxStore.filter: ThreadFilter` exists, top-row chips update it,
  but the underlying `ValueObservation` SQL **does not filter on it**
  (find at `InboxStore.swift` `observeThreads()` / `currentRequest`).
- Account list in `RBSidebar` is a static `ForEach` — clicks don't
  bind to `composition.activeAccountID`, and `InboxStore` doesn't
  filter on accountID.
- `Persistence` package has **no label table at all**.
  `GmailMapper.mapMessage()` reads `dto.labelIds`, extracts UNREAD →
  `MessageRecord.flags`, SENT → `flags`, drops everything else. INBOX,
  STARRED, TRASH, SPAM, IMPORTANT, all user labels — gone.
- `ThreadView.swift:85` Archive button: `Button { /* Archive stub */
  }`. Snooze + Send-to are also stubs.
- `GmailAPIClient` exposes no `modifyThread(id:add:remove:)` method
  for label mutations.
- `SettingsFeature` has Accounts / Privacy / AI tabs but no language
  preference, no default-tone preference, no auto-translate toggle.
  `String(localized:)` calls hard-coded in views — no runtime locale
  override.
- No translation infrastructure. `NLLanguageRecognizer` not imported
  anywhere. Apple `Translation` framework (macOS 15+) not used.
- `BriefRail.swift` CTAs (`Draft reply` / `Snooze to Fri AM` /
  `Log to CRM`) wrap mid-word at 340px column width because labels
  lack `.lineLimit(1) + .minimumScaleFactor`. Inline composer's
  `Edit in full` / `Send` buttons same problem.

### Existing utilities to reuse (do not rewrite)
- `AppDatabase` (`Persistence`) + GRDB `ValueObservation` — all DB
  reads go through this; new `LabelRecord` joins to `MessageRecord`.
- `Migrator.swift` already has a versioned-migrations setup; add v2
  there, do NOT add ad-hoc migration code.
- `GmailDTO` types in `MailProviders/Gmail` — `dto.labelIds` is
  already parsed, we just stop dropping it.
- `MLXLLMRuntime` + `AIRuntime` package — the Gemma-loading code in
  `MLXThreadBriefService` is the template for `MLXThreadReplyService`.
- `EyebrowLabel`, `RBIconButton`, `SignalChip`, `RBToneSegment` in
  DesignSystem — reuse, do not duplicate.
- `ComposeViewModel` + `ComposeService` in `ComposeFeature` —
  `InlineComposer.onEditInFull` should hand the draft over to this
  existing flow.
- `extractEmail(from:)`, `prefillComposeForReply()` in `MainScene.swift`
  — call site for new reply-language-detection.

## Success Criteria

Every one of these must hold on a fresh sync of `hlexxx@gmail.com`
(or any real Gmail account) with the existing 423-thread corpus:

1. **Sidebar folders work.** Click Inbox → only INBOX-labeled threads.
   Click Archive → only threads without INBOX/TRASH/SPAM/SENT/DRAFT.
   Click Sent → only SENT-labeled threads (drops own-sent-to-others
   too). Click Starred → only STARRED. Click on an account row →
   thread list filtered to that account's threads, all other folders
   recount.
2. **Top-row filter chips work.** "Needs reply" filters to threads
   the AI brief flagged as requesting action. "Has deadline" filters
   to threads with non-null `brief.deadline`. "Attachments" filters
   to threads with ≥ 1 attachment. "AI handled" filters to threads
   with a brief.
3. **Folder counts reactive.** Right-aligned count badges update
   without restart when threads are archived/starred/marked-read.
4. **HTML emails render.** Russian promotional mail with full HTML
   (CSS, inline imgs, links) shows the layout, not just a snippet.
   Remote tracker pixels stay blocked by default. A per-message
   "Load remote images" toggle appears in the head when the message
   has remote `<img>` references.
5. **AI brief uses real body.** On a 5-paragraph email, brief
   summary mentions actual content, not the 10-word snippet.
6. **Composer is real AI.** Open any thread. Tone segment Concise /
   Warm / Direct generates **three different drafts** each time
   you switch — visible on subsequent threads, not the same "Hi Marta"
   paragraph. Regenerate produces a different draft each click. Edit
   in full hands the current draft to `ComposeWindow` for editing.
7. **Reply language matches thread.** Open a Russian thread, switch
   to Compose, AI generates the reply in Russian. UI eyebrow shows
   "Drafted in RU".
8. **Archive works.** Hit Archive on a thread → it disappears from
   Inbox locally AND in the Gmail web UI (verify by reloading
   mail.google.com). Star toggle works the same way.
9. **Translation tab appears when needed.** With Settings →
   Preferred language = English, open a Russian thread. A segmented
   control **Original / Translated** appears at the top of the
   reading pane. Tap Translated → message body shows in English,
   translated on-device via Apple `Translation`. No network.
10. **Right-rail layout no longer breaks.** "Draft reply", "Snooze
    to Fri AM", "Log to CRM", "Edit in full", "Regenerate", "Send"
    — none of them split mid-word at 340px (brief rail width).

## Validation Commands

```bash
PROJ=/Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos

cd $PROJ && tuist generate --no-open
cd $PROJ && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
cd $PROJ && swiftlint --strict
cd $PROJ/Packages/Core/Persistence && swift test
cd $PROJ/Packages/Mail/MailProviders && swift test
cd $PROJ/Packages/Mail/MailSync && swift test
cd $PROJ/Packages/Mail/MailIndex && swift test
cd $PROJ/Packages/AI/AIKit && swift test
cd $PROJ/Packages/AI/AIRuntime && swift test
cd $PROJ/Packages/Features/InboxFeature && swift test
cd $PROJ/Packages/Features/ThreadFeature && swift test
cd $PROJ/Packages/Features/BriefFeature && swift test
cd $PROJ/Packages/Features/ComposeFeature && swift test
cd $PROJ/Packages/Features/SettingsFeature && swift test
cd $PROJ && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build
```

---

### Task 1: Schema migration v2 (labels)

Add label graph to `Persistence`. Migration is idempotent + reversible
within the same DB session (don't drop columns yet — Phase 2 can clean
up `flags` once Task 2 is stable).

- [ ] Create `Packages/Core/Persistence/Sources/Persistence/Records/LabelRecord.swift`:
      ```swift
      public struct LabelRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
          public static let databaseTableName = "label"
          public var id: String          // PK; "INBOX", "STARRED", "Label_12345"
          public var accountId: String   // FK → account.id
          public var name: String        // human-readable, "Inbox", "Promotions", user label name
          public var type: LabelType     // .system | .user | .category
          public var color: String?      // hex from Gmail user labels, null for system
          public var messagesUnreadCount: Int  // mirror of Gmail API field, refreshed on labels.list
          public var messagesTotalCount: Int
          enum CodingKeys: String, CodingKey {
              case id, accountId = "account_id", name, type
              case color, messagesUnreadCount = "messages_unread_count"
              case messagesTotalCount = "messages_total_count"
          }
      }
      public enum LabelType: String, Codable, Sendable {
          case system, user, category
      }
      ```
- [ ] Create `Packages/Core/Persistence/Sources/Persistence/Records/ThreadLabelRecord.swift`:
      ```swift
      public struct ThreadLabelRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
          public static let databaseTableName = "thread_label"
          public var threadId: String  // FK → thread.id
          public var labelId: String   // FK → label.id
          enum CodingKeys: String, CodingKey {
              case threadId = "thread_id", labelId = "label_id"
          }
      }
      ```
- [ ] Open `Packages/Core/Persistence/Sources/Persistence/Migrator.swift`
      and add a `v2` migration after the existing `v1`:
      ```swift
      migrator.registerMigration("v2_labels") { db in
          try db.create(table: "label") { t in
              t.primaryKey("id", .text)
              t.column("account_id", .text).notNull().references("account", onDelete: .cascade)
              t.column("name", .text).notNull()
              t.column("type", .text).notNull()
              t.column("color", .text)
              t.column("messages_unread_count", .integer).notNull().defaults(to: 0)
              t.column("messages_total_count", .integer).notNull().defaults(to: 0)
          }
          try db.create(table: "thread_label") { t in
              t.primaryKey {
                  t.column("thread_id", .text).notNull().references("thread", onDelete: .cascade)
                  t.column("label_id", .text).notNull().references("label", onDelete: .cascade)
              }
          }
          try db.create(index: "idx_thread_label_label", on: "thread_label", columns: ["label_id"])
          try db.create(index: "idx_thread_label_thread", on: "thread_label", columns: ["thread_id"])
          // Seed canonical system labels so folder queries work even
          // before the first labels.list sync. accountId left null is
          // fine — we'll insert per-account on labels.list.
      }
      ```
- [ ] Add `Packages/Core/Persistence/Tests/PersistenceTests/LabelMigrationTests.swift`:
      open empty DB, run migrator, assert tables `label` + `thread_label`
      exist, assert v2 idempotent on second run.
- [ ] Run `cd $PROJ/Packages/Core/Persistence && swift test`.

### Task 2: Label-aware Gmail sync

Capture `labelIds` from API into the new tables, fetch user labels.

- [ ] Add `GmailDTO.Label` in
      `Packages/Mail/MailProviders/Sources/MailProviders/Gmail/GmailDTO.swift`:
      ```swift
      public struct Label: Decodable, Sendable {
          public let id: String
          public let name: String
          public let type: String          // "system" | "user"
          public let color: ColorInfo?
          public let messagesUnread: Int?
          public let messagesTotal: Int?
          public struct ColorInfo: Decodable, Sendable {
              public let backgroundColor: String?
              public let textColor: String?
          }
      }
      ```
- [ ] Add `GmailEndpoint.listLabels` + `GmailAPIClient.listLabels()` →
      `[GmailDTO.Label]` (calls
      `GET /users/me/labels`).
- [ ] In `Bootstrap.swift`: before the first `pages` loop, call
      `let labels = try await api.listLabels()`; UPSERT into `label`
      table (mapping `type: "system"` → `.system`,
      `name.hasPrefix("CATEGORY_")` → `.category`, else `.user`).
      Yield 0.02 progress for the labels-fetch phase.
- [ ] Modify `GmailMapper.mapMessage()` to **return** `labelIds: [String]`
      alongside the existing `MailDomain.Message`. (Easiest: a new
      tuple-returning method `mapMessageWithLabels(_:)`; keep
      `mapMessage` for tests that don't need labels.)
- [ ] In the bootstrap/incremental persister (find the `db.write` block
      that UPSERTs `MessageRecord` / `ThreadRecord`): for each message,
      after upserting, DELETE existing `thread_label` rows for this
      thread (only those from the labels we just observed — keep
      client-side adds from Task 6 not yet reconciled) and INSERT the
      new set. Use thread-level labels: a thread carries the union of
      labels from its messages, but Gmail returns labels per-message,
      so build the union: `labelIds = Set(messages.flatMap(\.labelIds))`.
- [ ] In `IncrementalSync.swift`: when `history.list` returns
      `labelsAdded` / `labelsRemoved`, apply them to `thread_label`
      directly (do not re-fetch the whole thread for label changes
      alone). The history entries already include the threadId + label
      ids in the delta.
- [ ] Add `Packages/Mail/MailSync/Tests/MailSyncTests/LabelRoundTripTests.swift`:
      seed an account, run a fake `GmailAPI` returning a thread with
      labels `["INBOX","STARRED","Label_x"]` → assert 3 rows in
      `thread_label`, 3 rows in `label`. Run a second sync where
      `STARRED` is removed → assert only 2 rows in `thread_label`.
- [ ] Run `cd $PROJ/Packages/Mail/MailSync && swift test`.

### Task 3: Sidebar wiring + label-driven filtering

Now make folder / account clicks change what's in the thread list.

- [ ] Create `SidebarSelection` in `Apps/MacApp/Sources/Views/RBSidebar.swift`:
      ```swift
      enum SidebarSelection: Hashable {
          case folder(FolderID)
          case account(String)
          case allAccountsAllFolders
          // default = .folder(.inbox)
      }
      enum FolderID: String, Hashable {
          case inbox, needsReply, hasDeadline, attachments
          case logged, starred, sent, archive
          var gmailLabel: String? {
              switch self {
              case .inbox: return "INBOX"
              case .sent:  return "SENT"
              case .starred: return "STARRED"
              case .archive: return nil  // = negative filter
              default: return nil  // brief/attachment-derived
              }
          }
      }
      ```
- [ ] Extend `RBSidebar` view: add `@Binding var selection: SidebarSelection`.
      Each folder row + account row uses `.onTapGesture { selection =
      .folder(...)/.account(...) }`. Highlight the selected row with
      `rbAccentSoft` background.
- [ ] In `MainScene.swift`: add `@State private var sidebarSelection:
      SidebarSelection = .folder(.inbox)` and pass it to `RBSidebar`.
      On `.onChange(of: sidebarSelection)` call
      `inboxStore.setSelection(sidebarSelection)`.
- [ ] In `InboxStore`: replace the existing `ValueObservation` request
      with one that joins `thread` ⨝ `thread_label` filtered by:
      - if `selection.account != nil` → `WHERE thread.account_id = ?`
      - if `selection.folder.gmailLabel != nil` → `WHERE thread.id IN
        (SELECT thread_id FROM thread_label WHERE label_id = ?)`
      - if `selection.folder == .archive` → `WHERE thread.id NOT IN
        (SELECT thread_id FROM thread_label WHERE label_id IN
        ('INBOX','TRASH','SPAM','SENT','DRAFT'))`
      - if `selection.folder == .attachments` → `WHERE EXISTS (SELECT 1
        FROM message m JOIN attachment a ON a.message_id = m.id WHERE
        m.thread_id = thread.id)`
      - if `.needsReply` / `.hasDeadline` / `.aiHandled` → JOIN to a new
        `thread_brief` table from Task 5's caching (or for now: filter
        by presence of brief row).
- [ ] Folder counts: add `InboxStore.folderCounts: [FolderID: Int]`
      computed from the same observation, surfaced to `RBSidebar`.
- [ ] Top-row filter chips (`InboxView.filterChips`): keep the chip UI,
      but the chip selection is an **additional** narrowing over the
      sidebar selection (set intersection). The chip state lives in
      `InboxStore.chipFilter: ChipFilter?` and is OR'd / AND'd inside
      the SQL.
- [ ] Account-click in `RBSidebar`: also updates `composition.activeAccountID`
      so newly-composed mail uses that account by default.
- [ ] Add snapshot tests for `RBSidebar` with each selection state
      highlighted.
- [ ] Add `InboxFeatureTests/InboxStoreFilterTests.swift`: seed 5 threads
      across 2 accounts with varying labels, assert `setSelection`
      produces the expected thread-ID set for each folder/account combo.
- [ ] Run `cd $PROJ/Packages/Features/InboxFeature && swift test`.

### Task 4: HTML body rendering

Show the actual email, with privacy-by-default for remote content.

- [ ] Create `Packages/Features/ThreadFeature/Sources/ThreadFeature/MessageBodyView.swift`:
      a SwiftUI view that takes `MessageRecord` + `[AttachmentRecord]`.
      - If `bodyHtml != nil` → render via `HTMLWebView` (new
        `NSViewRepresentable` wrapper around `WKWebView`).
      - Else if `bodyText != nil` → render as
        `Text(message.bodyText)` styled per Re:Box.
      - Else snippet fallback as today.
- [ ] Create `HTMLWebView` (`NSViewRepresentable`):
      - `WKWebViewConfiguration` with `preferences.javaScriptEnabled = false`
        (default), `defaultWebpagePreferences.allowsContentJavaScript =
        false`.
      - Inject CSP via `WKUserContentController`:
        `default-src 'none'; img-src cid: data: 'none'; style-src
        'unsafe-inline'; font-src data:`. Block all remote loads unless
        `allowRemoteImages` flag.
      - `WKNavigationDelegate.decidePolicyFor`: deny everything except
        the initial loadHTMLString.
      - Mount as a `Coordinator`-managed `WKWebView` sized to its
        intrinsic content (use the `evaluateJavaScript("document.body
        .scrollHeight")` trick to feed back natural height to the
        SwiftUI parent — keep it bounded to a sensible max, e.g.
        2000pt, with internal scrolling above that).
      - Resolve `cid:` references in `src=` to the corresponding
        `attachment` row, encode as `data:` URL inline.
- [ ] Add `MessageBodyView.allowRemoteImages: Bool` + UI control in
      `ThreadView`'s head: an inline pill "Remote images blocked · Show
      images" that flips the flag for the open thread. Persist this
      decision per `from` address (new `trusted_sender(account_id,
      from_addr)` table — Task 1 migration follow-up: add to v2 or v3).
- [ ] Update `ThreadView.swift:234` site: replace
      `Text(message.bodyText)` with `MessageBodyView(message:
      message, attachments: ...)`.
- [ ] In `BriefStore.fetchThreadInput()` (line ~104): change
      `bodyText: msg.bodyText ?? msg.snippet ?? ""` to use a helper
      `Message.bestPlainText` that returns `bodyText ?? htmlToPlain
      (bodyHtml) ?? snippet ?? ""`. Add `htmlToPlain` helper in
      `Persistence` or a new `MailUtils` package — uses
      `NSAttributedString(data: htmlData, options:
      [.documentType: .html])` then `.string`. Strip URLs / repeated
      blank lines.
- [ ] Add snapshot tests in `ThreadFeatureTests`: a fixture HTML email
      with inline cid: image renders without remote loads; same email
      with `allowRemoteImages=true` does not change the snapshot
      (because the fixture has no remote imgs) but assert the WKWebView
      config differs.
- [ ] Run `cd $PROJ/Packages/Features/ThreadFeature && swift test`.

### Task 5: AIService.draftReply + InlineComposer wired

Replace the hardcoded English `draftBodies` with real on-device output.

- [ ] Extend `AIService` protocol
      (`Packages/AI/AIKit/Sources/AIKit/AIService.swift`):
      ```swift
      public protocol AIService: Sendable {
          func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief
          func draftReply(
              _ input: AIThreadInput,
              tone: AIReplyTone,
              locale: Locale,                  // UI/system locale
              replyLanguage: String?           // BCP-47 like "ru", overrides locale for the output
          ) async throws -> AIThreadReply
      }
      public enum AIReplyTone: String, Sendable, CaseIterable {
          case concise, warm, direct
      }
      public struct AIThreadReply: Sendable, Equatable {
          public let body: String                  // plain text, ready to drop into TextEditor
          public let evidenceMessageIDs: [String]  // which messages from the thread the model cited
          public let detectedReplyLanguage: String // BCP-47, what the model actually output in
          public let confidence: Double
      }
      ```
- [ ] Create `Packages/AI/AIKit/Sources/AIKit/MLXThreadReplyService.swift`
      mirroring `MLXThreadBriefService`. Loads the same Gemma 4 E2B
      model (share the loaded model handle across both services via
      a single `MLXModelHost` actor).
- [ ] Add `Packages/AI/AIPrompts/Sources/AIPrompts/draft_reply_v1.txt`
      (or wherever prompt templates live) — instructed prompt with:
      - JSON-only output (schema validation).
      - Tone hint (concise/warm/direct).
      - "Respond in {replyLanguage}." inserted when non-nil.
      - Few-shot examples for each tone × ru/en.
      - "Cite which messages you used in evidenceMessageIDs."
- [ ] Wire `BriefStore`-style caching for replies in a new
      `ReplyStore` inside `ComposeFeature` (or a `DraftStore`
      sub-store). Cache key: `(threadID, latestMessageID, tone,
      replyLanguage)`. Invalidate on Regenerate.
- [ ] Rewrite `InlineComposer.swift`:
      - Replace `@State private var draftText: String` initialisation
        from `draftBodies[.warm]` with an `@State var draftText: String
        = ""` and `.task { await loadDraft(.warm) }`.
      - Replace `onChange(of: tone)` body — call
        `await replyStore.generate(threadID, tone, language)`.
      - Replace `Regenerate` button action — `await
        replyStore.regenerate(threadID, tone, language)`.
      - Replace `onSend` no-op — invoke existing `ComposeService` send
        path with `draftText`.
      - Add a loading-spinner overlay on the text-area when AI is
        running (use `RBTextStyle.body` ghost-text "Drafting…" if
        spinner is hard).
      - `Edit in full` (`onEditInFull` closure): emit current
        `draftText` to `ComposeViewModel.body` via the wiring in
        `MainScene.swift` and present `ComposeWindow`. (The full
        ComposeWindow is already wired in Step 7.)
      - Eyebrow label changes to include detected reply-language:
        "Drafted locally · tone: \(tone) · in \(replyLanguage)".
- [ ] Delete the `// TODO(§15-step-4)` comments — Step 10 closes them.
- [ ] Tests: `AIKitTests/MLXDraftReplyTests.swift` (gated on Apple
      Silicon CI runner like the existing brief test): assert each tone
      produces a body of distinct lengths, in the requested locale (use
      `NLLanguageRecognizer` to detect output language).
- [ ] Run `cd $PROJ/Packages/AI/AIKit && swift test` and
      `cd $PROJ/Packages/Features/ComposeFeature && swift test`.

### Task 6: Mutations — Archive / Star / Move-to-trash / Mark-read

Optimistic-then-server, label-driven, idempotent.

- [ ] Add `GmailAPIClient.modifyThread(id:addLabelIds:removeLabelIds:)
      async throws -> GmailDTO.Thread` — `POST
      /users/me/threads/{id}/modify` body `{ addLabelIds:[],
      removeLabelIds:[] }`.
- [ ] Add `MailMutator` actor in `MailSync`:
      ```swift
      public actor MailMutator {
          public func archive(_ threadId: String, accountId: String) async throws
          public func unarchive(_ threadId: String, accountId: String) async throws
          public func star(_ threadId: String, accountId: String) async throws
          public func unstar(_ threadId: String, accountId: String) async throws
          public func markRead(_ threadId: String, accountId: String, read: Bool) async throws
          public func trash(_ threadId: String, accountId: String) async throws
      }
      ```
      Each call:
      1. Optimistic local: insert/delete in `thread_label` (and
         `MessageRecord.flags` UNREAD bit for markRead) inside a
         `db.write`.
      2. API: `modifyThread(...)` with the appropriate add/remove pair
         (archive = removeLabelIds=["INBOX"], star =
         addLabelIds=["STARRED"], trash = addLabelIds=["TRASH"]).
      3. On API success: no-op (already applied locally).
      4. On API failure: rollback the local change, surface a toast.
- [ ] Wire to UI:
      - `ThreadView.head` Archive button: `Task { try await
        mutator.archive(threadId, accountId: ...) }`. Snooze stays
        stub for now (out of scope), Send-to stays stub.
      - Swipe-right on a `ThreadRow` in `InboxView` → archive.
        Swipe-left → trash.
      - Keyboard shortcuts (in `MainScene.swift` or
        `PrivateAIMailApp.swift`): `E` = archive, `S` = star, `K` =
        toggle read.
      - Add a brief toast bar at the bottom of MainWindow: "Archived
        — Undo". Undo within 8 s reverts the operation
        (`mutator.unarchive(...)`).
- [ ] Tests: `MailSyncTests/MailMutatorTests.swift` with a fake
      `GmailAPI` that records add/remove pairs, assert each method
      produces the correct payload + reverts on simulated 5xx.
- [ ] Run `cd $PROJ/Packages/Mail/MailSync && swift test`.

### Task 7: Translation tab (Apple Translation framework)

On-device, no network. macOS 15+ availability.

- [ ] New package `Packages/Features/TranslationFeature` — `Package.swift`
      + `TranslationStore.swift` + `TranslationView.swift`.
- [ ] `TranslationStore.detect(text:) async throws -> Locale.Language`
      using `NLLanguageRecognizer.dominantLanguage(for:)`.
- [ ] `TranslationStore.translate(text:to:) async throws -> String`
      using `import Translation` + `TranslationSession`. First call
      may prompt the user to download the language pair — that's
      expected behaviour; surface a one-shot "Language pack required"
      alert from the existing AI panel.
- [ ] In `ThreadView`: above the message stack, render a
      `RBSegmentedControl` with `Original / Translated` **only if**
      detected language ≠ `settings.preferredLanguage`. When
      Translated is selected, swap each message's body to its
      translated copy. Cache results in a new column
      `MessageRecord.translatedText` (one-language-at-a-time per
      message; Phase 2 adds multi-language cache table). Add to
      migration v2.
- [ ] AI inputs: when generating brief/reply, do NOT translate the
      input — feed the original body to the model. The model's prompt
      asks it to respond in `replyLanguage`. Translation is purely a
      reading affordance.
- [ ] Tests: `TranslationFeatureTests` with a Russian fixture string,
      assert `detect()` returns `ru` and `translate(to: "en")` returns
      a non-empty string containing some English-letter content.
      Skipped on macOS < 15.
- [ ] Run `cd $PROJ/Packages/Features/TranslationFeature && swift test`.

### Task 8: Reply-language detection routing

Make sure replies go out in the right language without user thinking.

- [ ] In `ComposeFeature.InlineComposer`: when entering a thread,
      compute `replyLanguage` from the **last incoming** message body
      via `TranslationStore.detect(text:)` (Task 7 dep). Default to
      `settings.preferredLanguage` if detection confidence is low /
      message is too short.
- [ ] Pass `replyLanguage` to every `AIService.draftReply(...)` call.
- [ ] Eyebrow in InlineComposer: show "Drafted in 🇷🇺 RU" (or just
      "in RU" if emoji-flag is too cute). Hovering shows full name.
- [ ] User override: small popup chevron next to eyebrow → list of
      languages from `Locale.availableIdentifiers` (filtered to the
      ~30 most common). Picking one re-runs `draftReply` with new
      language.
- [ ] Tests: `ComposeFeatureTests/ReplyLanguageRoutingTests.swift`:
      fake `AIService` that records the `replyLanguage` argument, assert
      RU thread → "ru" passed, EN thread → "en" passed, mixed thread
      with last message in DE → "de" passed.
- [ ] Run `cd $PROJ/Packages/Features/ComposeFeature && swift test`.

### Task 9: Right-pane layout fixes

Pixel-level. Test in both 1200pt and 1600pt window widths.

- [ ] `BriefRail.swift` CTAs: wrap each `Button { ... } label: { Label(...) }`
      in `.lineLimit(1)` + `.minimumScaleFactor(0.82)` +
      `.fixedSize(horizontal: false, vertical: true)`. Stack three
      buttons vertically on widths < 360pt (use a `ViewThatFits` or
      a `@Environment(\.horizontalSizeClass)` check; for macOS use
      `GeometryReader` to read the rail's width).
- [ ] `InlineComposer.ctaButtons`: same `.lineLimit(1) +
      .minimumScaleFactor(0.85)`. If composer width < 400pt, collapse
      "Edit in full" label to just an `pencil` icon (`RBIconButton`
      style), keep tooltip.
- [ ] Add a snapshot test row for each at 280pt / 340pt / 480pt
      widths in dark and light.
- [ ] Run `cd $PROJ/Packages/Features/BriefFeature && swift test`
      and `cd $PROJ/Packages/Features/ComposeFeature && swift test`.

### Task 10: Settings — language, default tone, auto-translate

- [ ] Add a **General** tab to `SettingsScene` (place it first, before
      Accounts). It contains:
      - `Preferred language` — `Picker("Preferred language",
        selection: $locale)`. Options: System default, English,
        Русский, Deutsch, Français, Español, Italiano, Português,
        中文 (简体), 中文 (繁體), 日本語, 한국어, العربية, हिन्दी,
        Türkçe, Polski, Nederlands. Stored in
        `@AppStorage("pam.preferredLanguage")` as BCP-47 (`""` for
        system).
      - `Default reply tone` — `Picker` over `AIReplyTone.allCases`.
        Stored in `@AppStorage("pam.defaultTone")`. `InlineComposer`
        reads this on appearance.
      - `Auto-translate foreign threads` — `Toggle`. When ON, the
        Translation tab from Task 7 defaults to "Translated" instead
        of "Original" when the detected language differs.
- [ ] Plumb the language preference through `CompositionRoot` into
      `ComposeViewModel`, `BriefStore`, `InlineComposer`, and the new
      `TranslationStore`. All `AIService` calls receive the explicit
      Locale.
- [ ] Tests: `SettingsFeatureTests/PreferencesPersistenceTests.swift`
      — set values via the store, restart, assert read.
- [ ] Run `cd $PROJ/Packages/Features/SettingsFeature && swift test`.

---

## Cross-cutting tasks

- [ ] Replace every remaining hardcoded English UI string (sidebar
      folders, filter chips, brief rail CTAs, action sheet tiles) with
      `String(localized: ..., bundle: .module)` calls and add Russian
      + German translations to the relevant `.xcstrings` catalogs as
      a sanity check that the i18n plumbing works end-to-end.
- [ ] Update `release-notes/v0.1.5-alpha.md` covering the visible
      changes (HTML rendering, real AI in composer, folder filters,
      archive, translation, multi-language). Include "How to test"
      checklist that maps 1:1 to the Success Criteria above.
- [ ] Bump `MARKETING_VERSION` to `0.1.5-alpha`, build to `105` in
      `Project.swift`.
- [ ] Update `EMAIL_ALF/14_macos_app_design.md` §15: mark step 10 ✅
      with the merge commit, copy this plan to `plans/fresh/completed/`.

## Critical files to read or modify

| Purpose | Path |
|---|---|
| Brief input pipeline (snippet fallback bug) | `Packages/Features/BriefFeature/Sources/BriefFeature/BriefStore.swift:104-136` |
| Composer stub | `Packages/Features/ComposeFeature/Sources/ComposeFeature/InlineComposer.swift:22-26,70-73,127-129` |
| AIService protocol | `Packages/AI/AIKit/Sources/AIKit/AIService.swift` (whole file) |
| Gmail mapper labels | `Packages/Mail/MailProviders/Sources/MailProviders/Gmail/GmailMapper.swift:17-19` |
| Persistence migrations | `Packages/Core/Persistence/Sources/Persistence/Migrator.swift` |
| Sidebar (no selection) | `Apps/MacApp/Sources/Views/RBSidebar.swift` (whole file) |
| MainScene wiring | `Apps/MacApp/Sources/Scenes/MainScene.swift:44,143-150` |
| ThreadView body | `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift:85 (archive stub), 234 (bodyText)` |
| Inbox filter | `Packages/Features/InboxFeature/Sources/InboxFeature/InboxStore.swift` |
| Gmail API client | `Packages/Mail/MailProviders/Sources/MailProviders/Gmail/GmailAPIClient.swift` |
| Settings | `Packages/Features/SettingsFeature/Sources/SettingsFeature/SettingsScene.swift` |
| Compose service (real send) | `Packages/Features/ComposeFeature/Sources/ComposeFeature/ComposeService.swift` |

## Existing functions and utilities to reuse (do not rewrite)

- `MLXThreadBriefService` → template for `MLXThreadReplyService`;
  share the `MLXModelHost` actor that loads Gemma so we don't load the
  model twice.
- `BriefStore`'s caching pattern (`briefCache[threadID] = CacheEntry(...)`
  + `latestMessageID` invalidation) → mirrors verbatim for replies and
  translations.
- `GmailAPIClient` retry/backoff middleware → `modifyThread` and
  `listLabels` ride the same code path.
- `EyebrowLabel`, `RBToneSegment`, `RBIconButton`, `SignalChip`,
  `LocalAIPill` in DesignSystem — all reused as-is.
- `ComposeViewModel` + `ComposeService` (Step 7) — `InlineComposer`
  hands off to these when user clicks **Edit in full**.
- `AccountsTabStore.observeSyncEvents(for:)` in `SettingsFeature` —
  the pattern for streaming `SyncEvent`s from `MailSyncEngine` is
  re-applied for mutation reconciliation.

## Verification (end-to-end smoke flow)

After Task 1–10 merge:

```bash
cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
tuist generate --no-open
xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
open ~/Library/Developer/Xcode/DerivedData/PrivateAIMail-*/Build/Products/Debug/PrivateAIMail.app
```

Inside the running app, on a real connected Gmail account (`hlexxx@gmail.com`):

1. Inbox shows only INBOX-labeled threads. Click Archive — different
   set, no INBOX. Click Sent — only own outgoing. Click Starred —
   only starred. Click hlexxx@gmail.com in the Accounts section —
   filters to that account; click "All accounts" (new top entry) to
   restore.
2. Open a long marketing email — full HTML layout rendered. A pill
   says "Remote images blocked". Click → images load. Open a Russian
   promotional email — same.
3. AI brief on a Russian email reads in Russian, summarizes the
   actual content (not the snippet).
4. Settings → General → Preferred language = English. The Russian
   email now shows an Original/Translated segmented control. Tap
   Translated — body switches to English.
5. With the same Russian email open, the inline composer eyebrow says
   "Drafted in RU". Switch tone Concise/Warm/Direct — three different
   Russian drafts appear. Click Regenerate — a 4th different one.
   Click Edit in full — `ComposeWindow` opens with that draft, in
   Russian, addressed to the right person.
6. Archive a thread from `ThreadView` head — disappears from Inbox.
   Open mail.google.com in Chrome — verify the thread is archived
   there too. Same flow for Star.
7. `xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme MacApp
   -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` exits with
   `** TEST SUCCEEDED **`. All package `swift test` suites pass.
8. `! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages
   --include='*.swift' --exclude-dir=Tests --exclude-dir=.build` —
   privacy gate clean.

## Out of scope for Step 10 (explicit non-goals)

- Push notifications via broker (still Step 8, Phase 2).
- Apple Intelligence FoundationModelsBackend (still Step 6, deferred).
- Spotlight search index for thread bodies.
- Calendar integration / Snooze persistence.
- Multi-recipient compose with autocomplete.
- Drag-and-drop attachments in composer.
- Smart unsubscribe.
- Microsoft 365 / Outlook provider (`MailProviders/Graph`).
- Per-message thread-level translation cache table v2 (covered by
  v3 migration in a future step).
- Re-enabling App Sandbox + switching to non-SPM Sparkle distribution
  with `InstallerLauncher.xpc` (covered when we leave alpha).
