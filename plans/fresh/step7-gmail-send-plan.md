# Step 7: Real Gmail Send + Composer Wiring

## Overview

Close the send-loop. Today the Composer window and the inline reply
composer both render correctly with all the design affordances —
to/cc/subject fields, NSTextView body, Send button — but Send is a
stub: it dismisses the sheet. After step 7, clicking Send actually
delivers the message through the Gmail REST API, the sent message
lands in the user's Gmail "Sent" folder, and it appears in the local
DB so it shows up in the in-app Sent view.

Per design doc §2 principle 5 (**Approvals на границе**), every
outgoing action must pass through an explicit user-approved gate. For
send that means an interstitial confirm before the request is fired,
plus a 5-second "undo" window in the UI.

Pre-flight: OAuth currently scopes `gmail.readonly` + `gmail.metadata`.
Sending requires `gmail.send`. The existing account has to re-consent —
that's the first task.

## Context

- Step 4 (on-device AI brief) merged into `main` (`e809bc7`). The whole
  AI stack works. Real Gmail data flows through `InboxStore` /
  `ThreadStore`. Two composer surfaces exist:
  - `Packages/Features/ComposeFeature/Sources/ComposeFeature/ComposeWindowView.swift` —
    full-screen modal opened via ⌘N. Currently hardcoded to/cc/subject
    fields (placeholder values "marta@acme.de" etc.); no thread
    context.
  - `Packages/Features/ComposeFeature/Sources/ComposeFeature/InlineComposer.swift` —
    the smaller composer inside the reading-pane. Wired to the thread
    via callbacks; Send button is currently no-op (see the
    `// TODO(§15-step-7): wire real send` comment in
    `Apps/MacApp/Sources/Scenes/MainScene.swift`).
- `Packages/Mail/MailProviders/Sources/MailProviders/Gmail/GmailAPI.swift`
  has four read methods (`listMessages`, `getMessage`, `getThread`,
  `listHistory`). No `sendMessage` yet — Task 4 adds it.
- `Packages/Auth/AuthKit/Sources/AuthKit/GmailOAuthConfig.swift` scopes
  list is `["gmail.readonly", "gmail.metadata"]`. Task 1 extends this.
- `Packages/Core/Persistence/Sources/Persistence/Records/MessageRecord.swift`
  has the columns we need for inserting a sent message (`from_addr`,
  `to_addr`, `cc_addr`, `sent_at`, `body_text`, etc.). `MessageRecord`
  is already used by `MailSync` for inserts.
- `Packages/Mail/MailDomain/` exposes `Message`, `Address`, `Thread`
  value types from step 3 — reuse, don't redefine.
- `AIKit.threadBrief()` produces an `AIThreadBrief` with summary +
  `evidence` array; reply-drafting (the tone-segment UI in
  InlineComposer) is **out of scope** for step 7. Step 7.5 will wire
  `AIKit.draftReply(tone:)` if we go there. For now the body text in
  ComposeWindowView keeps its placeholder pre-fill but real users
  edit before sending — that's fine.

## Success Criteria

- New OAuth scope `https://www.googleapis.com/auth/gmail.send` is
  requested. Existing accounts that hit a `403 insufficientPermissions`
  on send get prompted to re-consent inline (one extra click); fresh
  accounts pick up the new scope on first connect.
- The Composer window can be opened from the inbox in two ways:
  1. ⌘N — empty new message addressed to nobody (user fills `to:`)
  2. "Reply" affordance in the reading pane / inline composer — pre-fills
     `to:` = original sender, `subject:` = `Re: <original>` (deduped if
     already prefixed), `body:` = empty (no autoquote in this iteration),
     and sets `In-Reply-To` + `References` headers so the message
     threads correctly in the recipient's client
- Clicking **Send** in either composer:
  1. Shows an inline approval row above the button: "Send to N
     recipient(s) on `<account.email>` — Send / Cancel" with a 5-second
     auto-undo countdown that, if not cancelled, fires the request
  2. After the countdown, calls `GmailAPI.sendMessage(raw:threadId:)`
     with the message as RFC 5322 MIME (base64url-encoded body wrapped
     in `Gmail Users.messages.send` request)
  3. On success: closes the composer, inserts a `MessageRecord` into
     the local DB with the returned Gmail message id + thread id, plays
     a subtle Sent toast, returns focus to the inbox
  4. On error: shows the error inline (don't dismiss), offers Retry +
     Cancel. Error states distinguish auth (`401`), insufficient scope
     (`403 insufficientPermissions`), quota (`429`), and generic 5xx
- Sent messages appear in the **Sent** sidebar folder within 1 second
  (insert is immediate; the next incremental sync replaces the local
  record with the canonical one from Gmail)
- `MessageRecord.flags` bit for "sent by me" is set so the threadlist
  rows can render the "→ me sent" affordance per design
- OAuth refresh on send-401 works exactly like for read calls (existing
  retry path in `GmailAPIClient`)
- Privacy gates intact:
    - `Subject:`, `To:`, body content **never** logged
    - Network grep finds no `print` / `Logger` / `os_log` of message
      fields
    - Step-3-style content-leak grep still passes
- `xcodebuild build` → `** BUILD SUCCEEDED **`
- `swiftlint --strict` → 0 violations
- All per-package `swift test` runs exit 0; new test counts:
    - `AuthKitTests`: +1 (scope set includes `gmail.send`)
    - `MailProvidersTests`: +6 (MIME builder happy path, address
      escaping, multi-recipient, attachment-free reply with In-Reply-To,
      sendMessage 200, sendMessage 403 → propagates insufficient-scope)
    - `ComposeFeatureTests`: +5 (approval row appears on Send tap,
      countdown auto-fires after 5 s, cancel halts the request,
      reply-prefill pre-fills to/subject from a thread fixture,
      thread-aware subject deduplicates `Re: Re:`)
    - One new XCTest UI smoke that opens compose, types into the body,
      clicks Send through the approval row, and asserts a fake
      `MockGmailAPI` recorded the send (the UI test runs against a
      seeded fake API)

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && tuist generate --no-open`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && swiftlint --strict`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Auth/AuthKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Features/ComposeFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Mail/MailSync && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && ! grep -rnE '(os_log|Logger|print|debugPrint)\(.*\b(toField|ccField|subjectField|bodyText|messageBody|subject|body)\b' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build`

### Task 1: Extend OAuth scopes with gmail.send

Add the send scope to the requested set. New accounts pick it up on
first authorize; existing accounts handle it on demand via Task 3's
re-consent path.

- [x] Open `Packages/Auth/AuthKit/Sources/AuthKit/GmailOAuthConfig.swift`
- [x] Append `"https://www.googleapis.com/auth/gmail.send"` to the default `scopes` array. Keep `gmail.readonly` and `gmail.metadata`. **Do not** swap to `gmail.modify` — that's broader than we need; least-privilege wins
- [x] Update the test in `AuthKitTests` that asserts the default scope set; it should now include the three scopes in a defined order (write the test to use `Set` comparison to avoid order brittleness)
- [x] Run `cd Packages/Auth/AuthKit && swift test`

### Task 2: GmailAPI.sendMessage + GmailDTO.SentMessage + endpoint

Wire the actual REST call. Gmail's [users.messages.send](https://developers.google.com/gmail/api/reference/rest/v1/users.messages/send)
takes a base64url-encoded RFC 5322 message in `raw`, optionally a
`threadId` for replies, returns the canonical message with its
assigned `id` and `threadId`.

- [x] Add a method to `Packages/Mail/MailProviders/Sources/MailProviders/Gmail/GmailAPI.swift`: `func sendMessage(raw base64URL: String, threadId: String?) async throws -> GmailDTO.SentMessage`
- [x] Add a `GmailDTO.SentMessage` struct with `id: String`, `threadId: String`, `labelIds: [String]?` decoded from the API response (Codable, snake-case decoder already configured)
- [x] Add endpoint helper to `GmailEndpoint.swift` for `POST https://gmail.googleapis.com/gmail/v1/users/me/messages/send`
- [x] Implement in `GmailAPIClient.swift`:
    - `URLRequest` with `POST` method, JSON body `{"raw": "<base64url>", "threadId": "..."}` (omit `threadId` when nil)
    - Reuse the existing token-refresh-on-401 retry path
    - Distinguish `403` with response error `insufficientPermissions` → throw a new typed error `GmailAPIError.insufficientScope`
    - On `429` → backoff per existing rate-limit policy
- [x] Add fixtures under `Tests/MailProvidersTests/Fixtures/gmail/`:
    - `send_success.json` — canonical response for a successful send
    - `send_insufficient_scope.json` — the 403 body with `insufficientPermissions` reason
- [x] Tests in `Tests/MailProvidersTests/GmailAPIClientTests.swift`:
    - Happy path send 200 → returns `SentMessage` with non-empty id
    - 403 insufficient scope → throws `GmailAPIError.insufficientScope`
    - 401 → token refresh → retry → 200
    - 429 → backoff path (same fixture style as existing)
- [x] Run `cd Packages/Mail/MailProviders && swift test`

### Task 3: SMTP-like MIME builder (RFC 5322 + Gmail base64url framing)

A pure-Swift helper that takes structured compose data and emits the
base64url-encoded MIME blob that `sendMessage` expects. No third-party
deps — `Foundation` only.

- [x] Add `Packages/Mail/MailProviders/Sources/MailProviders/Gmail/MIMEBuilder.swift` exposing `public enum MIMEBuilder` with `static func encode(_ message: OutgoingMessage) throws -> String` (returns the base64url-encoded RFC 5322 message ready for `raw:`)
- [x] Add `Packages/Mail/MailDomain/Sources/MailDomain/OutgoingMessage.swift`: a Sendable struct with `from: Address`, `to: [Address]`, `cc: [Address]`, `bcc: [Address]`, `subject: String`, `body: String` (UTF-8 plain text; HTML is a follow-up), `inReplyTo: String?` (RFC 2822 Message-ID), `references: [String]` (thread chain)
- [x] MIME builder:
    - `Date:` header in RFC 5322 format
    - `Message-ID:` header generated locally (uuid@hlexx.privateaimail) — deterministic from a passed-in seed for tests
    - `From:`, `To:`, `Cc:`, `Bcc:` headers built from `Address` values, properly RFC 2047-encoded for non-ASCII display names
    - `Subject:` RFC 2047-encoded if non-ASCII
    - `In-Reply-To:` and `References:` headers when present
    - `Content-Type: text/plain; charset=utf-8`
    - `Content-Transfer-Encoding: quoted-printable`
    - CRLF line endings everywhere (Gmail rejects bare LFs)
    - Body wrapped to ≤ 76 chars per RFC 5322 §2.1.1
    - Base64url-encode the assembled bytes (Gmail's spec: standard base64 with `+`→`-`, `/`→`_`, optional padding stripping)
- [x] Tests in `Tests/MailProvidersTests/MIMEBuilderTests.swift`:
    - Plain ASCII subject + body → expected verbatim header block (use a fixture)
    - UTF-8 subject ("Контракт — Acme") → RFC 2047 encoded correctly (use a fixture; encoded form is stable)
    - Multi-recipient `To:` and `Cc:` produce comma-separated address lists
    - `inReplyTo` populates both `In-Reply-To` and prepends to `References`
    - Output is valid base64url (no `+`, no `/`, no whitespace)
    - Round-trip: decode the base64url, parse with a known-good library reference (or hand-roll a `MIMEParser` helper limited to what we need), assert all fields match
- [x] Run `cd Packages/Mail/MailProviders && swift test`

### Task 4: ComposeService — bridge ComposeFeature ↔ GmailAPI + DB

A small service that orchestrates: take editor state, build MIME,
call `sendMessage`, insert local record. Lives in a new file inside
`ComposeFeature` so feature-package contains the workflow; the
service depends on `GmailAPI` (protocol) and `AppDatabase`.

- [x] Add `Packages/Features/ComposeFeature/Sources/ComposeFeature/ComposeService.swift` exposing `public protocol ComposeService: Sendable` with `func send(_ draft: ComposeDraft) async throws -> SentEcho`
- [x] `ComposeDraft` struct: `accountID: String`, `from: Address`, `to: [Address]`, `cc: [Address]`, `bcc: [Address]`, `subject: String`, `body: String`, `replyContext: ReplyContext?` (Sendable)
- [x] `ReplyContext` struct: `threadID: String`, `inReplyToMessageID: String`, `referencesChain: [String]`
- [x] `SentEcho`: the values needed to insert the local row — `messageID`, `threadID`, `sentAt`
- [x] `LiveComposeService` implementation:
    1. Validate `to.count >= 1`; else throw `ComposeError.noRecipients`
    2. Build `OutgoingMessage` from draft + reply context
    3. `let raw = try MIMEBuilder.encode(outgoing)`
    4. `let sent = try await api.sendMessage(raw: raw, threadId: replyContext?.threadID)`
    5. On `GmailAPIError.insufficientScope` → throw `ComposeError.needsReconsent` (caller surfaces re-auth UI)
    6. Insert a `MessageRecord` via `@DatabaseActor` write: `flags |= sentByMe`, `from_addr = account.email`, etc.
    7. Return `SentEcho`
- [x] Add `MockComposeService` (in `Tests/ComposeFeatureTests/Support/`) for view tests
- [x] Wire `LiveComposeService` into `CompositionRoot` — instantiate one per active account, reuse the existing `GmailAPIClient` factory
- [x] Unit tests in `Tests/ComposeFeatureTests/ComposeServiceTests.swift`:
    - Happy path: send → DB has the new row → SentEcho values match
    - `insufficientScope` from API → throws `needsReconsent`
    - Empty `to:` → throws `noRecipients`
    - Generic API error → wraps as `ComposeError.send(underlying:)`
- [x] Run `cd Packages/Features/ComposeFeature && swift test`

### Task 5: Compose UI — approval row + Send wiring + reply-prefill

The visible behaviour change. Both composers get the same approval
+ Send wiring; the inline composer additionally gets reply pre-fill
from the active thread.

- [x] Add `ComposeFeature/ApprovalRow.swift`: a small horizontal bar showing recipient count + sending-account chip + `Cancel` / `Send` buttons. Uses `RBDuration.d3` (320 ms) eased animations from DesignSystem; styles per the design's button stack
- [x] State machine for the approval flow: `.idle → .awaitingApproval(deadline: Date) → .sending → .sent | .failed(Error)`. Single source of truth in a `@Observable final class ComposeViewModel`
- [x] Auto-fire timer: when `awaitingApproval`, schedule a `Task` that waits 5 seconds (`Task.sleep`), then transitions to `.sending` unless cancelled
- [x] **Cancel** during the 5 s window: cancels the Task, returns to `.idle`. No send is issued
- [x] **Cancel** during `.sending` (rare — Gmail API is fast but possible): aborts the URLSession task and returns to `.idle` with body intact
- [x] On `.sent`: dismiss the composer; emit a `NSUserNotification` "Sent" or an in-app toast (toast is a thin DesignSystem affordance — add `RBToast` view if not yet present)
- [x] On `.failed(.needsReconsent)`: keep the composer open, show inline error "This account hasn't granted send permission yet — Re-authorize". Re-auth button triggers `OAuthClient.authorize(scopes:)` for the `gmail.send` scope and on success retries the send
- [x] **Reply pre-fill in `InlineComposer`**: take a new `replyContext: ReplyContext?` parameter, derive `to:` from the original sender, `subject:` = original subject with `"Re: "` prepended (deduped — don't produce `"Re: Re: Re: ..."`), wire `MainScene` to pass the active thread's context. The trailing-closure callback to `MainScene` becomes a typed model now
- [x] **Compose entry from inbox without thread context**: ⌘N opens `ComposeWindowView` with empty fields; user types recipient by hand
- [x] **Account selector in compose**: a `Picker` showing connected accounts (already on `accountsTabStore` in CompositionRoot); current account defaults to the active account
- [x] Snapshot tests for the approval row (idle / awaiting-with-countdown / sending / failed) in dark + light
- [x] Run `cd Packages/Features/ComposeFeature && swift test`

### Task 6: Re-consent flow for existing accounts

Users who connected before step 7 only granted read scopes. On their
first send attempt the API returns 403. We need a smooth one-click
re-auth path.

- [x] In `AuthKit.GmailOAuthClient`, add `func reauthorize(accountID: String, additionalScopes: [String]) async throws -> AuthTokens`. Implementation: same PKCE flow but pass `prompt=consent` so Google re-shows the consent screen; specifically requests the union of the existing scopes + the new ones
- [x] In the re-consent UI from Task 5, call `reauthorize` and on success replay the original send via `ComposeService.send(_:)`
- [x] Persist the updated refresh token back to `KeychainTokenStore`
- [x] Test in `AuthKitTests`: refresh request body contains all expected scopes (table-driven)
- [x] Manual smoke (must run after the rest of the plan is wired):
    1. Connect a fresh Gmail account with the **old** scope set by temporarily reverting Task 1 (or use a feature flag to simulate)
    2. Restore Task 1
    3. Open compose, click Send → expect the re-consent inline row
    4. Click "Re-authorize" → browser flow → grant `gmail.send` → composer auto-retries → message sends

### Task 7: Sent message lands in local DB; Sent folder shows it

After a successful send, the local record needs to materialise so the
threadlist / Sent folder reflect the action immediately, before the
next sync round.

- [x] In `LiveComposeService.send`, after a successful API response:
    - Insert a `MessageRecord` with `id = sent.id`, `thread_id = sent.threadId`, `account_id = accountID`, `from_addr = "Display <account.email>"`, `to_addr = encoded recipients JSON`, `cc_addr = encoded`, `sent_at = now`, `body_text = draft.body`, `flags = sentByMe | read`
    - If `replyContext != nil`, the `thread_id` already exists; otherwise we're starting a new thread — insert a `ThreadRecord` too with `subject = draft.subject`, `last_message_at = now`, `message_count = 1`
    - All inserts on `@DatabaseActor`
- [x] Add a `flags` constants set in `MessageRecord`: `static let sentByMe = 1 << 0`, `static let read = 1 << 1`. Existing usages of flags (Inbox unread dot) shift to use named constants for legibility
- [x] Update `InboxStore` query: the Sent folder filter should match `(flags & sentByMe) != 0`. Verify the existing `FolderItem.id == "sent"` row in the sidebar drives the filter (may already; check)
- [x] Verify the next incremental sync replaces our locally-inserted row with the canonical one from Gmail (`UPSERT` semantics — Gmail's message id is stable, so our `INSERT OR REPLACE` keyed on `(account_id, id)` Just Works). Add a `MailSyncTests` regression test for this UPSERT path
- [x] Run `cd Packages/Mail/MailSync && swift test`

### Task 8: Privacy + final gate

- [ ] Add a content-leak grep to CI matching the new compose fields: `! grep -rnE '(os_log|Logger|print|debugPrint)\(.*\b(toField|ccField|subjectField|bodyText|messageBody|subject|body)\b' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build`
- [ ] Network-isolation: assert in `MailProvidersTests` that `sendMessage` issues exactly **one** outbound `URLSession` request (no implicit follow-ups, no telemetry hop); MockURLProtocol counts requests
- [ ] Run every validation command listed above; all exit 0
- [ ] Manual smoke (real Gmail account; cannot CI):
    1. Connect a fresh Gmail account (the new scope set is requested upfront, no re-consent needed)
    2. Open compose, address to your own email, type body, click Send → 5 s countdown → message is delivered → check Gmail web app to confirm the message arrived
    3. Click on a thread, open inline composer, click Reply → Send → message threads correctly under the original
    4. Open the Sent folder in the sidebar → the just-sent messages are listed
    5. Disconnect the network, click Send → error inline + Retry button → reconnect → Retry succeeds
- [ ] Update `EMAIL_ALF/14_macos_app_design.md` §15 step 7 from ⏭️ → ✅ with the merge commit hash. Tag `step7-complete`
