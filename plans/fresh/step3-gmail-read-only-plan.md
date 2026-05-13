# Step 3: Gmail Read-Only Sync on a Single Account

## Overview

First functional iteration on top of the skeleton. Connects one Gmail account
via OAuth, persists threads/messages to a local SQLite database via GRDB, and
renders real threads in the 3-pane MacApp UI. Read-only: no send, no compose,
no AI. Push notifications are out of scope — refresh is on-demand and on a
polling timer.

Plan file is meant to be executed against the **`private-ai-mail-macos`** repo
(sibling of `EMAIL_ALF/`). Architectural reference: `EMAIL_ALF/14_macos_app_design.md`
(v0.2), in particular §6 (data layer), §7 (mail sync), §10 (concurrency), §11
(security/sandbox).

## Context

- Skeleton iteration is complete on `master` of `private-ai-mail-macos`
  (commit `44cdad7`). 24 SwiftPM packages exist with stub `public enum
  <Name>` types and one passing test each.
- `MacApp` builds successfully via Tuist + xcodebuild. The window renders
  a `NavigationSplitView` with `ContentUnavailableView` placeholders in
  the middle and right columns.
- `Packages/Auth/AuthKit/` is empty. No OAuth code exists yet.
- `Packages/Mail/MailProviders/` is empty. No Gmail client exists yet.
- `Packages/Core/Persistence/` declares GRDB as a dependency in
  `Package.swift` but has no schema, no `DatabaseActor`, and no migrator.
- `Packages/Mail/MailSync/` is empty. The state machine described in
  §7.2 of the design doc is unimplemented.
- `Packages/Features/InboxFeature/` and `ThreadFeature/` exist as stubs
  but are not yet wired into `MainScene.swift`.
- Bundle id is `com.hlexx.privateaimail`. Sandbox container path is
  `~/Library/Containers/com.hlexx.privateaimail/`.
- MLX is intentionally not linked in skeleton (see `NOTES.md`). Do not
  re-add it in this step.
- A Go push-broker exists in a sibling repo `private-ai-mail-broker/`.
  Do **not** integrate with it here — this step is polling-only.

## Success Criteria

- A first-time user can open MacApp, click "Add Gmail account" in
  Settings → Accounts, complete the Google OAuth flow in the system
  browser, and within 60 seconds see the last 30 days of their Gmail
  threads in the middle pane sorted by `last_message_at DESC`.
- Selecting a thread shows raw plain text of its messages in the right
  pane (no formatting, no AI brief).
- Cmd+R triggers an incremental sync via Gmail `users.history.list` and
  the UI updates without restart.
- All OAuth refresh tokens are stored exclusively in macOS Keychain.
  No tokens in `UserDefaults`, plist files, or anywhere on disk.
- The broker and any telemetry receive zero raw email content. Logs may
  contain `account_id`, `message_id`, `thread_id`, counts, and durations
  — never `Subject`, `From`, `To`, `Body`, or `Snippet`.
- `xcodebuild build -scheme MacApp` exits with `** BUILD SUCCEEDED **`.
- `swiftlint --strict` reports 0 violations.
- All per-package `swift test` runs exit 0.
- `xcodebuild test -scheme MacApp` exits with `** TEST SUCCEEDED **` on
  a UI test that asserts a seeded thread renders end-to-end.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && tuist generate --no-open`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && swiftlint --strict`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Auth/AuthKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build`

### Task 1: Implement OAuth client and Keychain token store in AuthKit

Build the OAuth 2.0 Authorization Code + PKCE flow for Gmail. Use
`ASWebAuthenticationSession` (via `AuthenticationServices`). Refresh tokens
must round-trip through `KeychainTokenStore` and never appear in logs or
plain files. Register the custom URL scheme `com.hlexx.privateaimail` in
`Apps/MacApp/Info.plist` `CFBundleURLTypes`.

- [x] Add `OAuthClient` protocol and `GmailOAuthClient` struct in `Packages/Auth/AuthKit/Sources/AuthKit/OAuthClient.swift`
- [x] Add `GmailOAuthConfig` with client id placeholder and scopes `gmail.readonly`, `gmail.metadata`, `userinfo.email`
- [x] Implement `PKCE.generate()` returning `(verifier, challenge)` per RFC 7636 with `S256` challenge method
- [x] Implement `KeychainTokenStore` in `KeychainTokenStore.swift` wrapping `SecItemAdd/Copy/Delete` with `kSecAttrAccessibleAfterFirstUnlock` and service `com.hlexx.privateaimail.oauth`
- [x] Wire `GmailOAuthClient.authorize()` to launch `ASWebAuthenticationSession` with the prefersEphemeralWebBrowserSession option off so existing Google sessions can be reused
- [x] Implement `GmailOAuthClient.refresh(_:)` calling `https://oauth2.googleapis.com/token` with `grant_type=refresh_token`
- [x] Define `AuthError` enum: `cancelled`, `denied`, `network(Error)`, `decode(Error)`, `keychain(OSStatus)`
- [x] Register URL scheme `com.hlexx.privateaimail` in `Apps/MacApp/Info.plist` under `CFBundleURLTypes`
- [x] Add unit tests in `Packages/Auth/AuthKit/Tests/AuthKitTests/` covering PKCE verifier/challenge derivation against RFC 7636 test vectors, Keychain round-trip via in-memory mock, refresh request body matches Google docs (table-driven)
- [x] Ensure no code path logs `accessToken`, `refreshToken`, or the `Authorization` header value
- [x] Run `cd Packages/Auth/AuthKit && swift test`

### Task 2: Implement Gmail REST API client in MailProviders

Build a `URLSession`-based client for the Gmail REST API with retry and
backoff. Token injection and refresh-on-401 are handled internally so feature
code consumes a clean `GmailAPI` protocol. No third-party HTTP libraries.

- [x] Add `GmailAPI` protocol in `Packages/Mail/MailProviders/Sources/MailProviders/Gmail/GmailAPI.swift` with methods `listHistory`, `listMessages`, `getThread`, `getMessage`
- [x] Add `GmailEndpoint` enum building URLs for `users.history.list`, `users.messages.list`, `users.threads.get`, `users.messages.get`
- [x] Add `GmailDTO.swift` with `Codable` structs mirroring Gmail API JSON: `MessageList`, `Message`, `Thread`, `History`, `HistoryRecord`, `MessagePart`, `MessagePartBody`, `MessagePartHeader`
- [x] Add `GmailMapper.swift` converting `GmailDTO.Message` to `MailDomain.Message` and introduce `MailDomain.Message`, `Thread`, `Address`, `Attachment` value types in `MailDomain` if missing
- [x] Implement `GmailAPIClient` with `URLSession.shared` configured with `httpCookieStorage = nil` and `urlCache = nil`
- [x] Implement token refresh: on 401, call `OAuthClient.refresh(_:)`, retry the original request exactly once
- [x] Implement backoff: on 429 or 5xx, exponential backoff with jitter (base 500 ms, factor 2, max 5 retries, max total 30 s)
- [x] Add `RateLimiter` (sliding-window, 250 quota units per second; reference Gmail's per-method quota table)
- [x] Add `URLProtocol`-based mock in `Tests/MailProvidersTests/Mocks/MockURLProtocol.swift` and JSON fixtures under `Tests/MailProvidersTests/Fixtures/gmail/`
- [x] Add tests: `listMessages` happy path, 401 → refresh → retry → 200, 429 → backoff → success within budget, `GmailMapper` against a `messages.get?format=metadata` fixture and a `?format=full` fixture
- [x] Run `cd Packages/Mail/MailProviders && swift test`

### Task 3: Schema, migrator, and DatabaseActor in Persistence

Create the SQLite schema for accounts, threads, messages, attachments, and
sync state. Enforce the single-writer pattern via a `@globalActor`
`DatabaseActor`. All writes are isolated to that actor; reads use GRDB
`ValueObservation`.

- [x] Add `@globalActor public actor DatabaseActor` in `Packages/Core/Persistence/Sources/Persistence/DatabaseActor.swift`
- [x] Add `AppDatabase` struct in `AppDatabase.swift` exposing `dbQueue: DatabaseQueue`, factory `open(at:)`, and helpers `read`/`write` that route writes through `DatabaseActor`
- [x] Add `Migrator.swift` building a `DatabaseMigrator` and registering `M001_InitialSchema`
- [x] Implement `M001_InitialSchema` creating tables `account`, `sync_state`, `thread`, `message`, `attachment` with indexes per the schema below
- [x] Add GRDB record types `AccountRecord`, `ThreadRecord`, `MessageRecord`, `AttachmentRecord`, `SyncStateRecord` conforming to `FetchableRecord & PersistableRecord & Codable`
- [x] Default DB path: `Application Support/PrivateAIMail/db.sqlite` inside the sandbox container; expose `open(inMemory:)` for tests
- [x] Add tests: migrator applies M001 to empty DB and all expected tables exist, re-running migrator is a no-op, foreign-key cascade verified (delete account → child rows removed), `@DatabaseActor` isolation prevents off-actor writes (compile-time check via a `@Test` that imports the module)
- [x] Run `cd Packages/Core/Persistence && swift test`

Schema reference for this task:

```sql
CREATE TABLE account (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL CHECK (provider IN ('gmail')),
  email TEXT NOT NULL,
  display_name TEXT,
  created_at INTEGER NOT NULL,
  last_synced_at INTEGER
);

CREATE TABLE sync_state (
  account_id TEXT PRIMARY KEY REFERENCES account(id) ON DELETE CASCADE,
  history_id TEXT,
  last_bootstrap_at INTEGER,
  status TEXT NOT NULL DEFAULT 'idle'
);

CREATE TABLE thread (
  id TEXT NOT NULL,
  account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  subject TEXT,
  snippet TEXT,
  last_message_at INTEGER NOT NULL,
  message_count INTEGER NOT NULL DEFAULT 0,
  has_unread INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, id)
);
CREATE INDEX idx_thread_last_message ON thread(account_id, last_message_at DESC);

CREATE TABLE message (
  id TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  message_id_header TEXT,
  from_addr TEXT,
  to_addr TEXT,
  cc_addr TEXT,
  sent_at INTEGER NOT NULL,
  snippet TEXT,
  body_html_path TEXT,
  body_text_path TEXT,
  flags INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, id)
);
CREATE INDEX idx_message_thread ON message(account_id, thread_id, sent_at);

CREATE TABLE attachment (
  id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  filename TEXT,
  mime TEXT,
  size_bytes INTEGER,
  PRIMARY KEY (account_id, message_id, id)
);
```

### Task 4: MailSync engine — bootstrap and incremental

Combine the Gmail API client and Persistence into a per-account sync actor.
Bootstrap pulls 30 days of threads; incremental sync applies diffs via
`users.history.list`. State machine: `idle → bootstrapping → live ↔ paused →
degraded`.

- [x] Add `actor MailSyncEngine` in `Packages/Mail/MailSync/Sources/MailSync/MailSyncEngine.swift` with one instance per `accountId`
- [x] Implement `Bootstrap.run()`: page through `users.messages.list?q=newer_than:30d`, fetch threads in batches of 50 via `users.threads.get?format=metadata` with max 5 concurrent requests, upsert into `thread` + `message` via `DatabaseActor`, capture initial `historyId` into `sync_state`
- [x] Implement `IncrementalSync.run()`: page through `users.history.list?startHistoryId=<stored>` until exhausted, apply each `History` record's `messagesAdded`/`messagesDeleted`/`labelsAdded`/`labelsRemoved` to the DB, bump `sync_state.history_id`
- [x] Add `SyncSupervisor` in `SyncSupervisor.swift` holding the dictionary of per-account engines and exposing `start(accountId:)`, `refresh(accountId:)`, `stop(accountId:)`
- [x] Add `enum SyncEvent { case progress(Double), threadUpserted(ThreadID), error(SyncError), state(SyncState) }` and expose `AsyncStream<SyncEvent>` per account with buffer 64 dropOldest
- [x] Handle 429: move state to `paused`, schedule retry honoring `Retry-After` header up to 5 minutes, then resume
- [x] Idempotency: re-running bootstrap on populated DB produces the same row counts (no duplicates)
- [x] Add tests: bootstrap inserts N threads / M messages from fixture, incremental `messageAdded` extends an existing thread, incremental `messageDeleted` decrements `thread.message_count`, 429 triggers `paused` and retry, re-bootstrap is idempotent
- [x] Run `cd Packages/Mail/MailSync && swift test`

### Task 5: Wire InboxFeature and ThreadFeature into MainScene

Replace the placeholder columns in `Apps/MacApp/Sources/Scenes/MainScene.swift`
with real bindings to the database. Use GRDB `ValueObservation` bridged to
`AsyncSequence` so SwiftUI views observe changes without polling.

- [ ] Add `@Observable final class InboxStore` in `Packages/Features/InboxFeature/Sources/InboxFeature/InboxStore.swift` exposing `threads: [ThreadRow]` and `selectedThreadID: ThreadID?`
- [ ] Add `InboxView` rendering a `List(selection:)` of `ThreadRow` (subject + snippet + relative date via `RelativeDateTimeFormatter`)
- [ ] Bridge `ValueObservation.tracking { db in try ThreadRow.fetchAll(db, ...) }.values` to `InboxStore` via `.task { for await rows in stream { ... } }`
- [ ] Add `@Observable final class ThreadStore` in `Packages/Features/ThreadFeature/Sources/ThreadFeature/ThreadStore.swift` exposing `messages: [MessageRow]` for the selected thread
- [ ] Add `ThreadView` rendering messages stacked vertically with header (from/date) and plain-text body
- [ ] Update `Apps/MacApp/Sources/Scenes/MainScene.swift`: middle column hosts `InboxView`, right column hosts `ThreadView`, sidebar shows account list bound to the `account` table
- [ ] Keep the `ContentUnavailableView` placeholders for the empty-state (zero accounts) — show real columns only when at least one account exists
- [ ] Add a `Cmd+R` `.keyboardShortcut` triggering `SyncSupervisor.refresh(...)` on the currently-selected account
- [ ] Add an XCTest UI test in `Apps/MacApp/Tests/InboxUITests.swift` that launches the app with a seeded in-memory DB containing one account + two threads + three messages, then asserts: sidebar contains the account row, thread list contains both threads with non-empty subjects, selecting the first thread shows its messages
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && tuist generate --no-open && xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme MacApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

### Task 6: Add Gmail account flow in Settings

Replace the "Coming soon" placeholder on the Accounts tab of the Settings
window. The Add Gmail button kicks off OAuth, persists the account row,
starts `MailSyncEngine.bootstrap()`, and surfaces sync progress.

- [ ] Add `AccountsTab` view in `Packages/Features/SettingsFeature/Sources/SettingsFeature/AccountsTab.swift` rendering a list of connected accounts and an "Add Gmail account" button
- [ ] Add `AddGmailFlow` view handling the OAuth lifecycle: idle → authorizing → fetching-profile → bootstrapping → done/error
- [ ] On successful authorize, call `users.getProfile` to get the user's email, insert an `account` row, store refresh token via `KeychainTokenStore`, call `SyncSupervisor.start(accountId:)`
- [ ] On error or user-cancel, surface inline error message and do not insert any row
- [ ] Update `Apps/MacApp/Sources/Scenes/SettingsScene.swift` to use `AccountsTab` in place of the placeholder
- [ ] Show a per-account `ProgressView` next to the row while `SyncState == .bootstrapping`
- [ ] Add a "Remove account" affordance that calls `SyncSupervisor.stop(accountId:)`, deletes the row (cascade clears threads/messages), and removes the Keychain entry
- [ ] Add a manual smoke note in `NOTES.md` describing the end-to-end flow: delete `~/Library/Containers/com.hlexx.privateaimail/`, run MacApp, add account, observe sidebar + thread list populating within 60 s
- [ ] Add a unit test for the `AccountsTab` view model covering add-success, add-error, and remove paths
- [ ] Run all validation commands listed above and confirm none fail

### Task 7: Verify no raw email content leaks anywhere

Final pass to guarantee the privacy promise. Greps the codebase for forbidden
patterns and reviews logging touch-points. Anything that handles `Subject`,
`From`, `To`, `Body`, or `Snippet` must do so without writing it to a logger,
telemetry, or the broker payload.

- [ ] Run `grep -rE '(os_log|Logger|print|debugPrint).*\b(subject|from|to|cc|body|snippet)\b' Apps Packages --include='*.swift'` and confirm no real matches (variable names that don't hit a log call are OK)
- [ ] Run `grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build` and confirm zero output
- [ ] Audit `URLSession` configuration: confirm `httpCookieStorage = nil`, `urlCache = nil`, `httpAdditionalHeaders` empty
- [ ] Confirm `KeychainTokenStore` does not include token values in any thrown `AuthError.keychain(OSStatus)` description
- [ ] Confirm `SyncEvent` enum's associated values carry only ids, counts, and timestamps — no content strings
- [ ] Run all validation commands listed above; all must exit 0
- [ ] Run `swiftlint --strict` and confirm 0 violations
- [ ] Confirm `xcodebuild build -scheme MacApp` ends with `** BUILD SUCCEEDED **`
- [ ] Confirm `xcodebuild test -scheme MacApp` ends with `** TEST SUCCEEDED **`
- [ ] Tag the commit `step3-complete` and update `EMAIL_ALF/14_macos_app_design.md` §15 step 3 status from `pending` to `done`
