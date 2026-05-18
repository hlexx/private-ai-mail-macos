# Step 11 — Persistent thread briefs + filter wiring + visible-state cleanup

## Overview

Step 10 landed `AIService.threadBrief()` and brief-driven sidebar/chip
filters in spec, but the brief data only lives in `BriefStore.briefCache`
(in-memory, per-session). The sidebar folders `Needs reply` /
`Has deadline` / `Logged` and the top-row chips `Needs reply` /
`Has deadline` / `AI handled` cannot see this data, so their SQL falls
back to `"1 = 0"` (always-empty result). Plus a handful of visible-state
bugs from the v0.1.5-alpha audit that didn't get closed.

Step 11 closes the data-persistence gap (Task 1–4), then sweeps the
remaining audit findings (Task 5–8).

## Context (verified 2026-05-18 against `main` at `f1367a4`)

### What's broken (audit findings)

- **`InboxStore.swift:270-273` and `:299-302`** — chip + sidebar filters
  for `.needsReply` / `.hasDeadline` / `.aiHandled` / `.logged` hardcode
  `"1 = 0"` in the SQL `conditions` array. The trail of TODO comments
  says `Brief-driven filters — no thread_brief table yet, return empty`.
  Plan promised these filters work end-to-end; they don't.
- **`BriefStore.swift:17`** — `briefCache: [String: CacheEntry]`
  in-memory dict. Briefs vanish on app restart and on every cold start
  (Gemma reloads, then re-summarises the same threads). No persistence,
  no shared view onto briefs from other modules.
- **`ThreadView.swift:282`** — `MessageBodyView(... attachments: [])`.
  Inline `<img src="cid:logo123@example">` references in HTML emails
  can't resolve to embedded image data → render as broken-image icons.
  The `attachment` rows are in the DB; just need to fetch them per
  message and pass through.
- **`ThreadView.swift:108`** — `Button { onStar?() } label: { Label(...,
  systemImage: "star") }`. Always renders the contour star icon. Toggle
  works in Gmail (label gets added) and locally (`thread_label` row
  appears), but the UI doesn't reflect the current starred state. No
  `isStarred` flag flows into the view.
- **Codex round-9 documented limitations (left intentionally):**
  - Folder counts on `RBSidebar` show totals across all accounts even
    when an account is selected (`InboxStore.folderCounts` SQL is
    account-agnostic).
  - Undo toast timer races: if user clicks Undo before 8s, the toast
    dismisses immediately but the background dismissal task continues
    and could clobber a newer toast. Equality check prevents the wrong
    toast from dismissing but the orphan task lingers.

### What's already there (reuse, don't rewrite)

- `Persistence.Migrator.swift` has versioned migrations; `v2_labels`
  was added in step 10. Add `v3_thread_brief` here.
- `MLXThreadBriefService` (Packages/AI/AIKit) — produces the
  `AIThreadBrief`. We just persist the result; no AI changes.
- `BriefStore.fetchThreadInput()` — DB read path. Reuse for the
  background queue runner.
- `MailSyncEngine` event stream (`SyncEvent.threadUpserted(threadId)`)
  — already emits a threadID every time a thread gets new messages.
  Step 11 subscribes to this stream to queue brief regen.
- `AttachmentRecord` in `Persistence/Records/AttachmentRecord.swift`
  — has `messageId`, `id`, `mime`, optional `data` field (verify).
  Already populated by `Bootstrap`.
- `MessageBodyView.HTMLWebView` (Packages/Features/ThreadFeature/...)
  — already has CSP allow-list including `img-src cid: data:`.
  Resolving cid → data is a string-substitution step before
  `loadHTMLString`.
- `ThreadLabelRecord` + `MailMutator.star/unstar` — toggling state
  works, just need to wire `isStarred` (= `STARRED` label exists for
  this thread) into `ThreadView`.

## Success Criteria

Verified on the same `hlexxx@gmail.com` corpus (423 threads, mixed
RU/EN, HTML-heavy):

1. **Reactive Needs-reply filter.** First-time sync silently summarises
   every inbox thread in the background. Click "Needs reply" chip or
   sidebar folder → only threads whose AI brief has `request != nil`.
   On a fresh thread with a real request ("can you confirm the seat
   count by Wednesday?"), the chip count increments within a few
   seconds of receiving the message.
2. **Reactive Has-deadline filter.** Same flow, predicate on
   `brief.deadline != nil`.
3. **AI handled chip.** Shows threads that have ANY brief generated.
   Count matches `SELECT COUNT(*) FROM thread_brief WHERE account_id =
   ?`.
4. **Briefs survive restart.** Open thread, brief loads instantly from
   DB (no Gemma spin-up). Quit + restart app, open same thread —
   instant again. Background re-summarisation triggers only when a
   thread gets new incoming messages.
5. **Folder counts respect account scoping.** Select hlexxx@gmail.com
   in sidebar → folder counts (Inbox / Starred / Sent / Archive)
   match that account only. Click "All accounts" → totals across all
   accounts.
6. **Star button visual state.** Open a thread that is starred in
   Gmail → ThreadView head shows a filled star (`star.fill`). Click
   to unstar → icon switches to contour (`star`). Click again to
   star → fills. State persists after reload.
7. **Inline CID images render.** A marketing email with a header
   logo embedded as `<img src="cid:logo@1.2.3">` shows the actual
   logo, not the broken-image placeholder. Remote `<img src="https://">`
   stays blocked until user clicks the "Show images" pill.
8. **Undo toast cancellation.** Click Archive → toast appears. Click
   Undo before 8s → toast dismisses immediately. Click Archive on a
   different thread before the previous timer would have expired →
   new toast appears, neither toast is clobbered, both timers behave
   independently. (Edge case: rapid Archive → Undo → Archive → Undo
   → Archive: no orphan toasts, no stuck timers.)

## Validation Commands

```bash
PROJ=/Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
cd $PROJ && tuist generate --no-open
cd $PROJ && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
cd $PROJ && swiftlint --strict
cd $PROJ/Packages/Core/Persistence && swift test
cd $PROJ/Packages/AI/AIKit && swift test
cd $PROJ/Packages/Features/BriefFeature && swift test
cd $PROJ/Packages/Features/InboxFeature && swift test
cd $PROJ/Packages/Features/ThreadFeature && swift test
cd $PROJ/Packages/Mail/MailSync && swift test
cd $PROJ && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build
```

---

### Task 1: `thread_brief` table — schema migration v3

Persistent storage for AI briefs. One row per `(account_id, thread_id)`.
Invalidation key: `latest_message_id`.

- [x] Create `Packages/Core/Persistence/Sources/Persistence/Records/ThreadBriefRecord.swift`:
      ```swift
      public struct ThreadBriefRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
          public static let databaseTableName = "thread_brief"
          public var accountId: String         // FK → account.id
          public var threadId: String          // FK → thread.id
          public var latestMessageId: String   // FK → message.id; invalidation key
          public var summary: String?
          public var request: String?          // null = no action requested (drives Needs reply chip)
          public var deadline: String?         // ISO-ish string; null = none (drives Has deadline chip)
          public var risk: String?
          public var nextStep: String?
          public var confidence: Double
          public var evidenceJson: String      // JSON-encoded [String]
          public var language: String?         // BCP-47 of source thread (for reply-language routing)
          public var generatedAt: Int          // unix timestamp
          enum CodingKeys: String, CodingKey {
              case accountId = "account_id"
              case threadId = "thread_id"
              case latestMessageId = "latest_message_id"
              case summary, request, deadline, risk
              case nextStep = "next_step"
              case confidence
              case evidenceJson = "evidence_json"
              case language
              case generatedAt = "generated_at"
          }
      }
      ```
- [x] Add `v3_thread_brief` migration to `Migrator.swift`:
      ```swift
      migrator.registerMigration("v3_thread_brief") { db in
          try db.create(table: "thread_brief") { t in
              t.primaryKey {
                  t.column("account_id", .text).notNull().references("account", onDelete: .cascade)
                  t.column("thread_id", .text).notNull().references("thread", onDelete: .cascade)
              }
              t.column("latest_message_id", .text).notNull()
              t.column("summary", .text)
              t.column("request", .text)
              t.column("deadline", .text)
              t.column("risk", .text)
              t.column("next_step", .text)
              t.column("confidence", .double).notNull().defaults(to: 0)
              t.column("evidence_json", .text).notNull().defaults(to: "[]")
              t.column("language", .text)
              t.column("generated_at", .integer).notNull()
          }
          try db.create(index: "idx_thread_brief_account", on: "thread_brief", columns: ["account_id"])
          try db.create(index: "idx_thread_brief_request", on: "thread_brief", columns: ["account_id", "request"])
          try db.create(index: "idx_thread_brief_deadline", on: "thread_brief", columns: ["account_id", "deadline"])
      }
      ```
- [x] Tests in `PersistenceTests/ThreadBriefMigrationTests.swift`: open
      empty DB → run migrator → assert table + 3 indices exist →
      round-trip a sample `ThreadBriefRecord` (insert + fetchOne).
- [x] Run `cd $PROJ/Packages/Core/Persistence && swift test`.

### Task 2: BriefStore persists every generated brief

`BriefStore` keeps its in-memory cache for fast UI access, but also
writes through to `thread_brief` on each successful generation. On
cache miss, first check the DB before invoking AIKit.

- [x] Modify `BriefStore.swift:`
      - Remove `briefCache: [String: CacheEntry]` in-memory dict
        OR keep it as a write-through L1 cache layered on the DB. (Pick
        whichever is cleaner; the DB is the source of truth.)
      - Add `func loadBrief(forThreadID:)` flow:
        1. If `threadID == nil` → `brief = nil`, return.
        2. Read latest message id from DB (already done via
           `fetchThreadInput`).
        3. SELECT from `thread_brief` WHERE `(account_id, thread_id) =
           (?, ?)`. If row exists AND `row.latest_message_id ==
           latestMessageID` → `self.brief = ThreadBriefViewData(from:
           row)`, return.
        4. Otherwise: run `aiService.threadBrief(input)` as today.
        5. On success: write/upsert into `thread_brief` (record
           contains: aiBrief fields + latest_message_id + accountId +
           generatedAt + detected language). Then set
           `self.brief = ThreadBriefViewData(from: aiBrief)`.
      - Use the existing `bestPlainText` helper from `MessageRecord`
        (no changes there).
- [x] Detect source-language for the brief: feed the
      concatenation of incoming-message bodies to
      `NLLanguageRecognizer.dominantLanguage(for:)`. Store the BCP-47
      code in `thread_brief.language`. This unblocks the `replyLanguage`
      routing in `InlineComposer` reading from a stable source.
- [x] Add `BriefStore.briefFor(threadID:) -> ThreadBriefViewData?`
      synchronous read-from-DB accessor for `InboxStore` to use in
      chip/folder filters (must be `@MainActor` but call into a
      `nonisolated db.read`).
- [x] Tests: `BriefFeatureTests/BriefPersistenceTests.swift` — fake
      `AIService`, generate once → assert DB row → reload store →
      assert no AI call on second `loadBrief(...)` for same thread →
      assert AI call DOES fire after `latest_message_id` changes.
- [x] Run `cd $PROJ/Packages/Features/BriefFeature && swift test`.

### Task 3: Background auto-brief generation queue

Today briefs only generate when the user opens a thread. With chip
filters needing briefs to decide "Needs reply", we need briefs for
every thread at some point. Generate in the background, throttled, on
incoming-message events.

- [x] Create `Packages/Features/BriefFeature/Sources/BriefFeature/BriefBackgroundQueue.swift`:
      ```swift
      @MainActor
      public final class BriefBackgroundQueue {
          private let aiService: any AIService
          private let db: AppDatabase
          private var pending: Set<ThreadKey> = []  // (accountId, threadId)
          private var workerTask: Task<Void, Never>?
          private let maxConcurrent = 1  // MLX is single-model; sequential is fine
          public init(aiService: any AIService, db: AppDatabase) { ... }
          public func enqueue(accountId: String, threadId: String) { ... }
          public func cancelAll() { ... }
          // worker pulls from pending one at a time, runs aiService.threadBrief,
          // writes thread_brief row, removes from pending. Repeats until empty.
      }
      ```
- [x] Wire into `CompositionRoot`: instantiate `BriefBackgroundQueue`
      alongside `BriefStore`, share the same `aiService` + `db`.
- [x] Wire into `MailSyncEngine` event stream: subscribe to
      `.threadUpserted(threadId)` events; for each, look up the thread's
      `accountId` and `enqueue(accountId, threadId)`. Use a debounce
      window of 1 s so a burst of messages on one thread generates only
      one brief.
- [x] First-time bootstrap: at the end of `MailSyncEngine.bootstrap()`,
      enqueue all threads in `INBOX` that don't have a brief yet
      (`SELECT thread.id FROM thread LEFT JOIN thread_brief ON ... WHERE
      thread_brief.thread_id IS NULL AND thread.id IN (... INBOX ...)`).
      Cap the initial backfill at 200 threads per account per launch to
      avoid hammering MLX for half an hour on first run; log the rest
      to a deferred queue.
- [x] User-facing progress: extend `SettingsScene → AI` tab with a row
      "Background briefs: X / Y generated" reading from
      `SELECT COUNT(*) FROM thread_brief vs SELECT COUNT(*) FROM thread`
      via `ValueObservation`.
- [x] Skip queue when `aiService` is unavailable (e.g. model not yet
      downloaded). Resume automatically when model loads.
- [x] Tests: `BriefFeatureTests/BriefBackgroundQueueTests.swift` —
      enqueue 5 threads → assert 5 thread_brief rows after worker
      drains → enqueue same thread twice → assert only one row +
      worker ran once.
- [x] Run `cd $PROJ/Packages/Features/BriefFeature && swift test`.

### Task 4: Wire chip + folder filters to `thread_brief`

Replace `"1 = 0"` with real SQL predicates.

- [ ] In `InboxStore.swift:270-273` (folder filters) and `:299-302`
      (chip filter), replace the empty-set placeholders with:
      ```swift
      case .needsReply:
          conditions.append("""
              EXISTS (
                  SELECT 1 FROM thread_brief tb
                  WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                    AND tb.request IS NOT NULL AND TRIM(tb.request) <> ''
              )
              """)
      case .hasDeadline:
          conditions.append("""
              EXISTS (
                  SELECT 1 FROM thread_brief tb
                  WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
                    AND tb.deadline IS NOT NULL AND TRIM(tb.deadline) <> ''
              )
              """)
      case .aiHandled:
          conditions.append("""
              EXISTS (
                  SELECT 1 FROM thread_brief tb
                  WHERE tb.account_id = t.account_id AND tb.thread_id = t.id
              )
              """)
      case .logged:
          // Phase 2 — CRM integration. Keep returning empty for now.
          conditions.append("1 = 0")
      ```
- [ ] Update `InboxStore.folderCounts` to count via the same predicates
      (use one query that GROUPs on each folder via CASE WHEN, or run
      the count queries in parallel via `ValueObservation`).
- [ ] Verify `InboxStore.observation` re-fires when `thread_brief`
      changes (`ValueObservation.tracking` must include `thread_brief`
      as a tracked table). Add it explicitly to the
      `Database.regions` set if needed.
- [ ] Tests: `InboxFeatureTests/ChipFilterTests.swift` — seed thread A
      with brief that has `request = "approve invoice"` → assert
      `.needsReply` chip returns thread A. Seed thread B with
      `deadline = "Friday"` → assert `.hasDeadline` returns B. Seed
      thread C with no brief → assert it appears under no chip except
      `.all` and `.attachments` if applicable.
- [ ] Run `cd $PROJ/Packages/Features/InboxFeature && swift test`.

### Task 5: Folder counts scoped to selected account

Today `folderCounts` shows totals across all accounts even when one
account is selected in the sidebar. Fix.

- [ ] In `InboxStore.swift`, find the `folderCounts` computation
      block. Pass the current `SidebarSelection` (or specifically its
      account scope) into the count SQL: when `.account(let id)` →
      `WHERE thread.account_id = ?`; when `.allAccountsAllFolders` →
      no account predicate; when `.folder(_)` → the existing
      `selectedAccountId` (default = active account).
- [ ] Snapshot tests in `InboxFeatureTests` covering single-account vs
      multi-account vs all-accounts folder counts.
- [ ] Run `cd $PROJ/Packages/Features/InboxFeature && swift test`.

### Task 6: Star button visual state in ThreadView

Reflect the current `STARRED`-label state of the open thread.

- [ ] Add `isStarred: Bool` to `ThreadView.swift`'s init (pass from
      `MainScene.swift` derived from `thread_label` query —
      `EXISTS (SELECT 1 FROM thread_label WHERE thread_id = ? AND
      label_id = 'STARRED')`).
- [ ] Modify line 108 to use the bound state:
      ```swift
      Button { onStar?() } label: {
          Label(
              isStarred
                  ? String(localized: "thread.action.unstar", defaultValue: "Unstar")
                  : String(localized: "thread.action.star", defaultValue: "Star"),
              systemImage: isStarred ? "star.fill" : "star"
          )
      }
      ```
- [ ] Wire `MainScene` to recompute `isStarred` whenever
      `inboxStore.selectedThreadID` changes — use the existing
      `ValueObservation` infrastructure on `thread_label` so the icon
      updates in real-time after the mutation lands.
- [ ] Snapshot tests in `ThreadFeatureTests` for both states in dark +
      light.
- [ ] Run `cd $PROJ/Packages/Features/ThreadFeature && swift test`.

### Task 7: Inline CID image resolution in HTML body

Make `<img src="cid:logo@…">` resolve to the embedded attachment data.

- [ ] In `ThreadView.swift:282`, replace `attachments: []` with the
      actual per-message attachment list (it's already in
      `MessageRow`/`MessageRecord` join, just plumb it through).
- [ ] In `MessageBodyView.HTMLWebView`, before `loadHTMLString`:
      ```swift
      var html = bodyHtml ?? ""
      for att in attachments where (att.mime ?? "").hasPrefix("image/") {
          // Gmail's Content-ID can appear as "logo@1.2.3" or "<logo@1.2.3>"
          guard let cid = att.contentId else { continue }
          guard let data = att.dataBase64 else { continue }
          let normalised = cid.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
          let dataURL = "data:\(att.mime ?? "image/png");base64,\(data)"
          html = html.replacingOccurrences(of: "cid:\(normalised)", with: dataURL)
          html = html.replacingOccurrences(of: "cid:<\(normalised)>", with: dataURL)
      }
      ```
- [ ] If `AttachmentRecord` doesn't currently expose `contentId` or
      raw `dataBase64`, add the columns to `AttachmentRecord` + migration
      v4 (or fold into v3) and populate from `GmailMapper`'s
      `extractAttachments`. Gmail returns `body.attachmentId` for the
      content-ID header — verify whether we have to download the
      attachment separately via `users.messages.attachments.get` and
      cache, or whether inline-encoded attachments arrive in the
      original payload. Most inline images come in `body.data` directly
      when the message format is `full`.
- [ ] CSP already allows `img-src data:` — no CSP change needed.
- [ ] Tests: a fixture HTML email with a tiny PNG embedded as cid:logo
      → assert the rendered HTML contains `data:image/png;base64,…` in
      place of `cid:logo`.
- [ ] Run `cd $PROJ/Packages/Features/ThreadFeature && swift test`.

### Task 8: Misc cleanup — Undo toast timer + htmlToPlainText consistency

- [ ] Find the Undo-toast implementation (likely in
      `MainSceneMutations.swift` or a `ToastStore` in the app target).
      Replace the orphan-task pattern with a proper `Task` reference
      stored on the store, cancelled on (a) Undo click, (b) new toast
      replacing this one. Snapshot the toast appearance + dismissal
      timing in a `MacAppTests` integration test if practical, else a
      unit test on the toast-store actor.
- [ ] Verify `MessageRecord.bestPlainText` is the single source of
      truth for plain-text extraction. Search for any remaining
      `NSAttributedString(html:` or regex-based html-strip in
      `BriefStore`, `ReplyStore`, `TranslationStore`. Route everything
      through `bestPlainText`. If `bestPlainText` uses
      `NSAttributedString` and that proves too slow for the
      background-brief queue (1000-thread bootstrap), add a
      `bestPlainText(fast:Bool)` variant that uses regex for the
      AI-input path while UI-display path keeps the rich
      `NSAttributedString` version. Document the trade-off in a
      comment.
- [ ] Run `cd $PROJ/Packages/Features/ComposeFeature && swift test`
      and `cd $PROJ/Packages/Features/BriefFeature && swift test`.

---

## Cross-cutting tasks

- [ ] Bump `MARKETING_VERSION` to `0.1.6-alpha`, `CURRENT_PROJECT_VERSION`
      to `106` in `Project.swift`.
- [ ] Write `release-notes/v0.1.6-alpha.md` listing the user-visible
      changes (Needs reply / Has deadline / AI handled chips actually
      work, briefs survive restart, star button reflects state, inline
      images in HTML emails render, folder counts respect account
      selection).
- [ ] Update `EMAIL_ALF/14_macos_app_design.md` §15: mark step 11 ✅
      with the merge commit, copy this plan to `plans/fresh/completed/`.

## Critical files to read or modify

| Purpose | Path |
|---|---|
| Audit findings #1+#2 (chip/sidebar filters) | `Packages/Features/InboxFeature/Sources/InboxFeature/InboxStore.swift:270-273,299-302` |
| In-memory brief cache (gone after Task 2) | `Packages/Features/BriefFeature/Sources/BriefFeature/BriefStore.swift:17` |
| CID image resolution gap | `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift:282` |
| Star visual gap | `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadView.swift:108` |
| Migrations | `Packages/Core/Persistence/Sources/Persistence/Migrator.swift` |
| Brief AI service surface | `Packages/AI/AIKit/Sources/AIKit/AIService.swift` |
| Sync events | `Packages/Mail/MailSync/Sources/MailSync/SyncEvent.swift` + `MailSyncEngine.swift` |
| HTML body wrapper | `Packages/Features/ThreadFeature/Sources/ThreadFeature/MessageBodyView.swift` |
| Composition root | `Apps/MacApp/Sources/CompositionRoot.swift` |
| Mutations + toast | `Apps/MacApp/Sources/Scenes/MainSceneMutations.swift` |

## Existing functions and utilities to reuse (do not rewrite)

- `MLXThreadBriefService.threadBrief` — no API change; just persist
  output.
- `BriefStore.fetchThreadInput` — same DB read path for the background
  queue worker.
- `NLLanguageRecognizer.dominantLanguage(for:)` — already imported in
  `TranslationStore`; reuse for `thread_brief.language`.
- `ValueObservation` — already wired throughout `InboxStore`;
  registering `thread_brief` as a tracked table is a one-line addition
  to existing observation block.
- `MailMutator.star/unstar` — unchanged; Task 6 just reads the
  resulting state.
- `GmailMapper.extractAttachments` — already returns attachment id +
  mime; Task 7 may need to extend it to also pass through
  `contentId` and `body.data` from the inline payload.

## Verification (end-to-end smoke flow)

After Task 1–8 land:

```bash
cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
tuist generate --no-open
xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
open ~/Library/Developer/Xcode/DerivedData/PrivateAIMail-*/Build/Products/Release/PrivateAIMail.app
```

On `hlexxx@gmail.com`:

1. First launch after install: Settings → AI shows "Background briefs:
   0 / 423 generated". Counter ticks up as Gemma chews through the
   backlog.
2. After ~50 briefs land, click `Needs reply` chip → some threads
   appear (those with `request != nil`). Click `Has deadline` → fewer
   threads. Click `AI handled` → all 50 ticked threads. Click `All` →
   everything back.
3. Quit app. Reopen. Open the same thread that had a brief — loads
   instantly (no spinner).
4. Star a thread → star icon fills immediately. Refresh from Gmail
   web → starred. Unstar → contour. State sticks.
5. Open a marketing email with an inline logo (Bybit / Lazada from
   the 0.1.5 screenshot) → the logo image appears, not a broken-image
   placeholder.
6. Select hlexxx@gmail.com in sidebar → folder counts on the right
   match that account's totals. Select "All accounts" → totals
   include the three demo accounts.
7. Archive → Undo → Archive → Undo (rapid). No stuck toasts, no
   orphan timers.
8. `xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme MacApp
   -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` exits `** TEST
   SUCCEEDED **`.

## Out of scope for Step 11 (defer to later)

- `Logged` folder + filter (CRM integration is Phase 2).
- Multi-locale brief output (brief is in source-thread language;
  cross-language brief is a future feature).
- Push notifications via broker.
- Outlook/Graph provider.
- Apple Intelligence FoundationModelsBackend.
- Snooze persistence + UI (still a stub).
- Send-to-other-app integration (Slack/Notion/HubSpot/CRM).
- Attachment Preview / Summarize (Phase 2).
