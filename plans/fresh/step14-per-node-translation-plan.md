# Step 14 — Per-text-node language detection for translation

## Overview

Step 12 added Apple `Translation` framework integration with HTML
preservation. It works for monolingual emails: open a Russian email,
hit Translated, get the same layout in English (or whatever the
preferred language is).

It silently fails on **bilingual emails**, which are extremely
common in real inboxes:

- Lazada Thailand order confirmation — 90 % English body, 10 % Thai
  navigation links. Detected dominant language = `en`. Translation
  Session configured as `en → en`. Result: nothing translates,
  Thai links stay Thai.
- Marketing mail with English body + e.g. Russian footer / sender
  greeting → same story.
- Reservation emails from international hotels with mixed
  EN/FR/DE chunks → same.

The user expects: clicking **Translated** translates **every** chunk
of text that is NOT in the preferred language to the preferred
language. Mixed-language emails are the default in many global
inboxes.

Step 14 closes this by detecting language **per-text-node**, then
running one `TranslationSession` per `(sourceLang → targetLang)`
pair.

## Context (verified 2026-05-20 against `main` at `e0955ea`)

### What's wrong

`Packages/Features/TranslationFeature/Sources/TranslationFeature/TranslationView.swift:117-140`
(`triggerTranslation` / `translateAll`):

```swift
guard let detected = detectedLanguage else { return }     // ← single language
let source = Locale.Language(identifier: detected)
let target = Locale.Language(identifier: effectivePreferredLanguage)
translationConfig = TranslationSession.Configuration(source: source, target: target)
```

Followed by:

```swift
for item in pending {
    let translated = try await session.translate(item.text)  // ← single session
    store.setTranslation(for: item.id, text: translated.targetText)
}
```

A single `TranslationSession` is bound to **one** language pair. If
the dominant language matches the target, the session becomes a
no-op for every text node, regardless of what individual nodes
actually contain.

The HTML pipeline (Step 12 Task 3) already extracts text nodes via
DOM walk and feeds them in batches — that infrastructure is correct
and reusable. Only the language-resolution stage is wrong.

### What stays the same

- DOM-walk extraction via `data-tx-id`/`data-tx-orig` from Step 12.
- `TranslationStore` cache shape:
  `translatedTexts: [messageId: String]` (plain-text emails) and
  `translatedNodes: [messageId: [nodeId: String]]` (HTML).
- Apply pipeline (`window.applyTranslations({n0: ..., n1: ...})`).
- Settings → Preferred language picker (Step 10 Task 10).
- The Original/Translated segmented control in `ThreadView`.

### What's reusable

- `NLLanguageRecognizer.dominantLanguage(for:)` already imported in
  `TranslationStore.detect(text:)`. Reuse for per-node detection.
- `NLLanguageRecognizer.languageHypotheses(withMaximum:)` — returns
  a `[NLLanguage: Double]` of candidates with confidence. Useful
  as a fallback when `dominantLanguage` returns nil (too short).
- `TranslationSession.translate(_:)` accepts individual strings;
  also accepts batched `[TranslationSession.Request]` via
  `translate(batch:)` (async sequence return).
- `effectivePreferredLanguage` already resolves "system" to the
  current OS locale; no change needed there.

## Success Criteria

Verified on `hlexxx@gmail.com` with the real bilingual emails the
user has in their inbox:

1. **Lazada Thailand order email (mostly EN + Thai nav links).**
   Click Translated. The 4 Thai navigation links translate to
   English. The English body stays English (no double-translation).
   Layout preserved.
2. **Marketing email with English body + Russian footer.** With
   preferred=English: footer translates to English, body
   unchanged. With preferred=Russian: body translates to Russian,
   footer unchanged.
3. **Single-language email (all Thai).** Backwards-compatible: works
   exactly as today.
4. **All English email with preferred=English.** Translated tab is
   visually identical to Original (no spurious translations, no
   spinner that hangs).
5. **Three-language email (EN + RU + DE).** All three foreign-to-
   preferred translations run in parallel. UI shows a single
   "Translating…" spinner while any session is in flight.
6. **Low-confidence detection (1-2-word fragments like "OK" or
   "Hi").** Skipped — preserved as-is. No false-positive flag as
   exotic language.
7. **No language pack downloaded.** Apple framework's native
   download prompt appears on first translation, same as today.
   After accept, subsequent translations proceed without prompt.
8. **Cache survives toggling.** Toggle Original → Translated →
   Original → Translated: no re-translation, instant render after
   first run for that message.

## Validation Commands

```bash
PROJ=/Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
cd $PROJ && tuist generate --no-open
cd $PROJ && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
cd $PROJ && swiftlint --strict
cd $PROJ/Packages/Features/TranslationFeature && swift test
cd $PROJ/Packages/Features/ThreadFeature && swift test
cd $PROJ && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build
```

---

### Task 1: Per-node language detection helper

Centralise the detection logic with confidence thresholds and short-
text handling. Used by Task 2's grouping pass.

- [x] Create
      `Packages/Features/TranslationFeature/Sources/TranslationFeature/NodeLanguageDetector.swift`:
      ```swift
      import NaturalLanguage
      import Foundation

      public struct DetectedLanguage: Sendable, Equatable {
          public let bcp47: String       // "en", "ru", "th", …
          public let confidence: Double  // 0…1
      }

      public enum NodeLanguageDetector {
          /// Detect the dominant language of a single text fragment.
          /// Returns `nil` for fragments shorter than `minimumLength`
          /// characters (default 4) — those are too noisy to detect
          /// reliably and should pass through untranslated.
          ///
          /// Strategy:
          /// 1. Try `NLLanguageRecognizer.dominantLanguage(for:)`. If
          ///    the recognizer's top hypothesis has confidence ≥ 0.5,
          ///    return it.
          /// 2. Otherwise return nil — caller treats the node as
          ///    "unknown" and preserves the original text.
          public static func detect(
              _ text: String,
              minimumLength: Int = 4,
              minimumConfidence: Double = 0.5
          ) -> DetectedLanguage? {
              let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
              guard trimmed.count >= minimumLength else { return nil }
              let recognizer = NLLanguageRecognizer()
              recognizer.processString(trimmed)
              let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
              guard let best = hypotheses.max(by: { $0.value < $1.value }),
                    best.value >= minimumConfidence else { return nil }
              return DetectedLanguage(bcp47: best.key.rawValue, confidence: best.value)
          }
      }
      ```
- [x] Tests in `TranslationFeatureTests/NodeLanguageDetectorTests.swift`:
      - English "Thanks for shopping with us!" → `en`, ≥ 0.6.
      - Thai "เติมเงิน & ดีลออนไลน์" → `th`, ≥ 0.6.
      - Russian "Здравствуйте, ваш заказ" → `ru`, ≥ 0.6.
      - "Hi" → nil (too short).
      - "OK" → nil (too short).
      - Empty string → nil.
      - 4-char fragment in unknown encoding → nil with low confidence.
- [x] Run `cd $PROJ/Packages/Features/TranslationFeature && swift test`.

### Task 2: Group nodes by source language

After DOM extraction returns `[(nodeId, text)]`, fan out detection
and group nodes by detected source. Skip nodes whose detected
language matches the preferred target. Skip nodes where detection
is nil.

- [x] Add to `TranslationStore` (or as a free function in a new file
      `TranslationGroupingService.swift`):
      ```swift
      struct NodeBatch {
          let sourceLanguage: String   // BCP-47
          let nodes: [(id: String, text: String)]
      }

      static func group(
          nodes: [(id: String, text: String)],
          preferredLanguage: String
      ) -> (batches: [NodeBatch], skipped: Set<String>) {
          var bySource: [String: [(String, String)]] = [:]
          var skipped: Set<String> = []
          for node in nodes {
              guard let detected = NodeLanguageDetector.detect(node.text) else {
                  skipped.insert(node.id)
                  continue
              }
              if detected.bcp47 == preferredLanguage {
                  // Same as target — render original; nothing to translate.
                  skipped.insert(node.id)
                  continue
              }
              bySource[detected.bcp47, default: []].append((node.id, node.text))
          }
          let batches = bySource.map { NodeBatch(sourceLanguage: $0.key, nodes: $0.value) }
          return (batches, skipped)
      }
      ```
- [x] Tests:
      - Lazada-shape input: 4 Thai links + ~30 EN nodes + preferred=en →
        1 batch (`th → en`, 4 nodes), 30 nodes skipped (already EN).
      - Mixed EN/RU input + preferred=en → 1 RU batch.
      - All-English input + preferred=en → 0 batches, every node skipped.
      - All-Thai input + preferred=en → 1 batch (`th → en`).
      - Empty input → 0 batches.

### Task 3: Multi-session translation pipeline

Replace the single `TranslationSession` with N sessions, one per
detected source language. Use the existing
`TranslationView.translationConfig` slot but make it a list.

- [x] Refactor `TranslationView` (`triggerTranslation` +
      `translateAll`):
      - Remove the single `translationConfig` state. Replace with
        `var pendingBatches: [NodeBatch] = []` and a chain of
        `.translationTask(...)` modifiers — one per batch.
      - On `triggerTranslation`: call `group(nodes:preferredLanguage:)`,
        store the result. For each batch, create a
        `TranslationSession.Configuration(source:, target:)` and
        attach a `.translationTask(config) { session in await
        translate(batch: batch, session: session) }`.
      - Skipped nodes get their `data-tx-orig` value re-applied in
        the apply step (already happens, since they have no entry in
        `translatedNodes[messageId]`).
- [x] Add the multi-task wrapper view in
      `TranslationToggleView.body`:
      ```swift
      ForEach(pendingBatches, id: \.sourceLanguage) { batch in
          Color.clear.frame(width: 0, height: 0)
              .translationTask(
                  TranslationSession.Configuration(
                      source: Locale.Language(identifier: batch.sourceLanguage),
                      target: Locale.Language(identifier: effectivePreferredLanguage)
                  )
              ) { session in
                  await translateBatch(batch, session: session)
              }
      }
      ```
      (Use a hidden 0x0 view to host each `.translationTask`. SwiftUI
      requires the modifier to live on a view; this is the canonical
      workaround for needing multiple sessions in parallel.)
- [x] In the `TranslationStore`: turn `isTranslating` into a counter
      (`inflightBatches: Int`) so the spinner is shown while ANY
      batch is in flight, and only cleared when all batches finish.
      Existing call sites (`setTranslating(true/false)`) become
      `incrementInflight()` / `decrementInflight()`.
- [x] On any batch error: store the error against the message id
      with the partial-success behaviour — translated batches stay
      cached, failed batches' nodes show original. Toast: "Some
      sections couldn't be translated."
- [x] Tests in `TranslationFeatureTests/MultiBatchTests.swift`:
      - Mock `TranslationSession` that returns `"[XX]<text>"` per
        source language. Verify that grouped output for a synthetic
        Lazada-shaped HTML produces correct per-node translations
        only for the Thai nodes.

### Task 4: Per-batch caching & invalidation

Cache must work per `(messageId, targetLanguage, sourceLanguage)`
so that switching preferred language re-translates only what's
needed.

- [ ] Update `TranslationStore.translatedNodes` to be:
      `[messageId: [nodeId: TranslatedFragment]]` where
      `TranslatedFragment { text: String; source: String; target: String }`.
- [ ] `apply()` JS step reads only fragments where
      `target == effectivePreferredLanguage`. Older fragments stay
      in cache but are ignored if target mismatches; they're
      garbage-collected when the message is freshly extracted.
- [ ] Cache hit-rate test: open a thread, switch tabs five times,
      assert TranslationSession was invoked exactly once per
      detected source group.

### Task 5: Settings reminder + Help-overlay note

Make the bilingual behaviour discoverable.

- [ ] Settings → General → Preferred language: append a help-line
      below the picker: "Only text in a different language is
      translated. Mixed-language emails translate only the
      non-preferred parts."
- [ ] Keyboard help overlay (Step 13): add a line under
      "Translation" section if absent: "⌃T toggle Original/Translated"
      (only if that shortcut already exists; otherwise skip).

### Task 6: Release notes + version bump

- [ ] Bump `MARKETING_VERSION` to `0.1.11-alpha`,
      `CURRENT_PROJECT_VERSION` to `111`.
- [ ] Write `release-notes/v0.1.11-alpha.md`:
      - Translation now handles mixed-language emails. Each text
        chunk is independently detected; only chunks NOT in the
        preferred language are translated. English-dominant emails
        with a few Thai/Russian/German fragments now show all
        non-English text translated. English text stays English.
      - Short fragments (≤ 3 chars) and low-confidence detections
        are preserved as-is.
      - Cache is per source-language pair: switching preferred
        language re-translates only what's needed.

---

## Critical files to read or modify

| Purpose | Path |
|---|---|
| Single-language detection + single session | `Packages/Features/TranslationFeature/Sources/TranslationFeature/TranslationView.swift:117-180` |
| Detection helper (now `TranslationStore.detect`) | `Packages/Features/TranslationFeature/Sources/TranslationFeature/TranslationStore.swift` |
| Translation cache | `TranslationStore.swift` (same file) |
| DOM walk + apply (untouched) | `Packages/Features/ThreadFeature/Sources/ThreadFeature/MessageBodyView.swift:HTMLWebView` |
| Settings preferred-language picker | `Packages/Features/SettingsFeature/Sources/SettingsFeature/GeneralTab.swift` (or whichever Settings view) |

## Existing functions and utilities to reuse (do not rewrite)

- `effectivePreferredLanguage` — already resolves "system" to OS
  locale; reuse as the canonical target.
- `NLLanguageRecognizer` — already imported in TranslationStore.
- DOM-walk extraction script (`data-tx-id`/`data-tx-orig`) — already
  installed by `MessageBodyView.HTMLWebView`; no changes.
- Apply-translations JS (`window.applyTranslations({...})`) — same.
- `TranslationStore.showTranslated` / `setError` / `setTranslating`
  — public surface unchanged, only the inflight counter behaviour
  changes.

## Verification (end-to-end smoke flow)

After Task 1–6:

```bash
cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos
tuist generate --no-open
xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
open ~/Library/Developer/Xcode/DerivedData/PrivateAIMail-*/Build/Products/Release/PrivateAIMail.app
```

On `hlexxx@gmail.com`:

1. Open the Lazada Thailand order confirmation email. Click
   **Translated**. The 4 Thai navigation links (เติมเงิน & ดีลออนไลน์,
   LazMall, คูปองลดจัดเต็ม, สินค้าชั้นนำจากต่างประเทศ) translate to
   English ("Top up & Online deals", "LazMall", "Discount Coupons",
   "Top International Products" or similar). The English body
   ("Your order has been delivered", "What's Next?", "Please let us
   know…") stays unchanged. Layout, fonts, colors — all preserved.
2. Open a fully-Russian email. Click Translated. The whole body
   translates to English. No regression vs Step 12.
3. Open a fully-English email with preferred=English. Click
   Translated. Toggle visually identical to Original (no
   re-rendering glitch, no spinner that hangs forever).
4. Settings → Preferred language → switch to Русский. Open the
   Lazada email again. Now the English body translates to Russian,
   the Thai links also translate to Russian.
5. `xcodebuild test -workspace PrivateAIMail.xcworkspace -scheme
   MacApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
   exits `** TEST SUCCEEDED **`.

## Non-regression contract

- Single-language Translated path (Step 12) keeps working.
- Plain-text emails (no `bodyHtml`) translation path keeps working
  via the existing single-session fallback.
- AI brief + composer pipelines untouched (they don't use
  `TranslationSession`).
- Keyboard shortcuts (Step 13) untouched.
- Label reconcile (Step 10/11/14) untouched.
- M008/M009/M010 unaffected.

## Out of scope for Step 14 (defer)

- Re-translation when the email's content changes after a Gmail
  edit (Gmail doesn't really edit, deferred).
- Persistent (DB-backed) translation cache — still in-memory only.
  `MessageRecord.translatedText` column from M004 remains
  unused.
- Custom translation-quality preferences (informal/formal tone) —
  Apple's framework doesn't expose this.
- Mixed-script detection beyond `NLLanguageRecognizer`'s
  capabilities (e.g. emoji-heavy text where the recognizer falls
  back to "und").
- Per-thread "always translate" override.
- A "Translate selection" right-click action.
