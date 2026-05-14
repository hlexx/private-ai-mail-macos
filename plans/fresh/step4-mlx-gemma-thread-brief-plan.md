# Step 4: On-device Thread Brief via MLX + Gemma 4

## Overview

First real AI feature in the product. Replaces the hardcoded brief stubs
that ship with `BriefStore` today with **on-device LLM inference** via
**Apple MLX** running **Gemma 4 IT, 4-bit quantised**. After this step
every thread (not just the two demo fixtures) gets a populated Re:Box
brief — summary, request, deadline, risk, next step, evidence,
confidence — generated locally on the user's Mac, with zero network
traffic at inference time.

Region-independent on purpose: the alternative (`FoundationModels` /
Apple Intelligence) is gated by region and by Apple Intelligence opt-in.
MLX + Gemma works on any Apple Silicon Mac running macOS 15+.

Step 4 deliberately inverts the original §15 ordering of design doc
`14_macos_app_design.md` (which placed FoundationModels first and MLX
second). FoundationModels remains a future opt-in optimisation, not a
dependency. See §14 decision 3 of the design doc: **MLX primary,
llama.cpp escape hatch**.

Weights ship via **download-on-first-launch** (~2.1 GB), not bundled.
The user sees a modal "Setting up local AI" screen with a resumable
progress bar the first time the app runs, then the model is cached in
`~/Library/Application Support/PrivateAIMail/models/` for all subsequent
launches and all accounts.

## Context

- Step 3 (Gmail read-only sync) merged into `main` (commit `f79b287`).
  Real Gmail threads/messages flow into `BriefStore` via the
  `selectedThreadID` watcher in `MainScene.swift`.
- The Re:Box UI iteration merged into `main` (commit `da9e957`).
  `BriefRail` UI exists and renders cleanly; it currently just receives
  a hardcoded `ThreadBrief` for thread IDs ending in `t1` or `t2`.
  Empty state for everything else.
- `Packages/AI/AIRuntime/Package.swift` and
  `Packages/AI/AIEmbeddings/Package.swift` **do not** currently depend
  on `mlx-swift`. That dep was dropped during the skeleton iteration to
  avoid forcing every CI run to download the Xcode Metal Toolchain
  before MLX was actually used. Re-adding it is Task 1 here.
- `Packages/AI/AIKit/Sources/AIKit/AIKit.swift` is a stub (`public enum
  AIKit { public static let moduleName = "AIKit" }`).
- `Packages/AI/AIPrompts/Sources/AIPrompts/AIPrompts.swift` is a stub.
- `Packages/AI/AIEvals/Sources/AIEvals/AIEvals.swift` is a stub.
- `Packages/Features/BriefFeature/Sources/BriefFeature/BriefStore.swift`
  has a `loadBrief(forThreadID:)` method with a `// TODO(§15-step-4):
  replace stub with AIKit.threadBrief()` comment marking the swap site.
- `Packages/Features/BriefFeature/Sources/BriefFeature/ThreadBriefViewData.swift`
  defines the view-model shape we need to populate.
- `Apps/MacApp/Sources/CompositionRoot.swift` owns `BriefStore` and
  passes it into `MainScene`. The `AIService` factory should hang off
  the composition root.
- `Apps/MacApp/Sources/DevSeeder.swift` (DEBUG-only) inserts 7 demo
  threads. They're the easiest local corpus to iterate against while
  building this step.
- macOS 15+ minimum deployment target (per current Tuist project). MLX
  Swift requires macOS 14+ so we're well above the floor.
- Apple Silicon only (we already require it for FoundationModels later
  and for SwiftUI MaterialView features). MLX has no Intel path.
- Design tokens for the AI affordances are already in DesignSystem:
  `Color.rbCitron500`, `Color.rbSignalLocalAi`, `Font.rbMono`, the
  Local-AI pill, etc. Don't define new ones; reuse.

## Success Criteria

- Selecting any thread populates the Brief Rail with a fresh,
  on-device-generated `ThreadBrief` containing every field
  (summary, request, deadline, risk, nextStep, evidence array,
  confidence). For purely-informational threads the structured output
  legitimately leaves `request`/`deadline`/`risk` as nil and the rail
  shows the "Nothing actionable" empty state.
- Brief generation latency on an M-series Mac:
    - p50 ≤ 2.5 s per thread brief
    - p95 ≤ 5.0 s
  Verified by the `AIEvals` runner over the demo corpus.
- No network traffic after the one-time model download. Confirmed by
  a network sniffer/`tcpdump`-style snapshot test that fails if any
  `URLSession.shared.dataTask` is issued from `AIRuntime`/`AIKit` at
  inference time.
- First-launch download UX: a blocking modal renders before the main
  window appears, shows a progress bar and bytes-downloaded counter,
  resumes from a partial download after a kill/restart, and writes
  weights atomically. Verified by deleting the weights dir, relaunching,
  and watching the UI.
- `BriefStore.loadBrief(forThreadID:)` no longer contains the
  hardcoded stubs. The `// TODO(§15-step-4)` comments are gone.
- Privacy: zero raw email content (subject, body, sender) ever appears
  in `os_log` / `Logger` / `print` / `debugPrint` calls in feature
  code. Re-applied step-3-style grep gate.
- `xcodebuild build` ends with `** BUILD SUCCEEDED **`.
- `swiftlint --strict` reports 0 violations.
- All per-package `swift test` runs exit 0. New tests:
    - `AIRuntimeTests`: prompt rendering, structured-output parsing
      against fixtures (no live MLX call in unit tests)
    - `AIKitTests`: `threadBrief()` happy path with a mock backend +
      one informational-thread path returning `nil` fields
    - `BriefFeatureTests`: store wires through the real `AIService`
      protocol (mock backend) instead of stubs
- `AIEvals` offline harness reports:
    - faithfulness ≥ 0.85 over the demo corpus (rough heuristic, not a
      ground-truth eval — see notes)
    - hallucination rate (entities not present in the source thread)
      < 5 %
    - JSON schema validity 100 %

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && tuist generate --no-open`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && swiftlint --strict`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/AI/AIRuntime && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/AI/AIPrompts && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/AI/AIKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/AI/AIEvals && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Features/BriefFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && ! grep -rE '(Subject:|Bearer |refresh_token)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && ! grep -rnE '(os_log|Logger|print|debugPrint)\(.*(subject|body|snippet|fromAddr|toAddr|message_id_header)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build`

### Task 1: Re-vendor mlx-swift in AIRuntime / AIEmbeddings and unblock Metal Toolchain in CI

The skeleton iteration intentionally dropped the mlx-swift SPM dependency
because MLX ships Metal shader source that requires the Xcode 26 Metal
Toolchain. Re-add the dep and the CI step. See `NOTES.md` "Why MLX is
not yet linked" for the previous rationale (the rationale stops applying
once we actually call MLX).

- [x] Add `.package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.20.0")` back to `Packages/AI/AIRuntime/Package.swift` and `Packages/AI/AIEmbeddings/Package.swift`. Re-pin to the latest tag in that minor series at the time of execution
- [x] Add `.product(name: "MLX", package: "mlx-swift")` to the target dependencies for both packages
- [x] In `.github/workflows/ci.yml`, add a `Download Metal Toolchain` step before the build job runs `xcodebuild build`: `sudo xcodebuild -downloadComponent MetalToolchain`. Cache the result via `actions/cache` keyed on Xcode version
- [x] Remove the "Why MLX is not yet linked" section from `NOTES.md` (or rewrite it to "MLX is linked; see Task 1 of step4-mlx-gemma-thread-brief-plan.md")
- [x] Run `tuist generate --no-open` and `xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Confirm the build still ends with `** BUILD SUCCEEDED **`
- [x] Run `cd Packages/AI/AIRuntime && swift test` and confirm the placeholder test still passes

### Task 2: Define the AIService protocol and ThreadBrief domain types

Establish a clean, backend-agnostic API. The Compose feature later in
§15 step 7 will reuse `AIService` for reply drafting, so design for that
now (a `Capability` enum is fine).

- [x] In `Packages/AI/AIKit/Sources/AIKit/`, add `AIService.swift` with `public protocol AIService: Sendable` exposing `func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief`
- [x] Add `AIThreadInput.swift` containing a `Sendable` struct with `messages: [AIThreadInput.Message]` and `attachments: [AIThreadInput.Attachment]` (filename + mime + page count only; no bytes). Each `Message` has `from`, `sentAt`, `bodyText` — all `String`/`Date`
- [x] Add `AIThreadBrief.swift` matching the existing `BriefFeature.ThreadBriefViewData` shape: `summary: String?`, `request: String?`, `deadline: String?`, `risk: String?`, `nextStep: String?`, `evidence: [String]`, `confidence: Double`
- [x] Add `AIError.swift` enum: `.modelNotInstalled`, `.modelLoadFailed(Error)`, `.inferenceFailed(Error)`, `.invalidStructuredOutput(String)`, `.cancelled`
- [x] Add a `MockAIService` in `Tests/AIKitTests/Support/` for unit tests of dependent features
- [x] Update `Packages/AI/AIKit/Sources/AIKit/AIKit.swift` to re-export the new public types
- [x] Run `cd Packages/AI/AIKit && swift test`

### Task 3: ModelManager — download, verify, and locate Gemma 4 weights

Self-contained component that downloads the 4-bit quantised Gemma 4 IT
weights from a mlx-community HuggingFace mirror, verifies SHA-256 of
each shard, and stores them under
`~/Library/Application Support/PrivateAIMail/models/gemma-4-it-4bit/`.
Resumable, atomic, observable.

- [x] Add `Packages/AI/AIRuntime/Sources/AIRuntime/ModelManager.swift` exposing `public actor ModelManager`
- [x] Public API: `installedURL() -> URL?`, `installedURL` returns non-nil only when the manifest matches the expected SHA-256
- [x] `func install(progress: @Sendable @escaping (Double, Int64, Int64) -> Void) async throws -> URL` — `(fraction, bytesDownloaded, totalBytes)`
- [x] Store the model identifier and expected manifest (file names + SHA-256 hex digests + total bytes) in a `GemmaModelSpec.swift` constant. Use `mlx-community/gemma-4-it-4bit` (or the equivalent mirror that exists at execution time — verify URLs are reachable). Pin specific revision
- [x] Implement resumable HTTP using `URLSession` with `Range:` headers; write each shard to a `.part` file and rename atomically on full match
- [x] On any SHA mismatch, delete the offending `.part` and retry the shard up to 3 times
- [x] Provide `func uninstall() throws` for tests
- [x] Add unit tests under `Tests/AIRuntimeTests/ModelManagerTests.swift` using a fake `URLProtocol` that serves a 1 KB fixture; verify happy path, resume after partial-write, SHA-mismatch retry, and cancellation
- [x] Run `cd Packages/AI/AIRuntime && swift test`

### Task 4: First-launch ModelSetup UX

A blocking SwiftUI scene that gates the main window. Renders when the
ModelManager reports the weights are missing or incomplete; goes away
when install completes. Resumes a partial download if the app was
killed during setup.

- [x] Add `Apps/MacApp/Sources/Scenes/ModelSetupScene.swift` — full-window view with the Re:Box typography: serif "Re:" mark, eyebrow label ("Setting up local AI · one-time"), progress bar styled with `Color.rbCitron500`, bytes-downloaded counter using `ByteCountFormatStyle.byteCount(style: .file)`
- [x] Add a `Cancel and quit` ghost button. Cancellation must stop the in-flight download and exit the app (no half-installed state allowed to proceed)
- [x] In `PrivateAIMailApp.swift`, gate the `MainScene` on a `@State setupComplete: Bool` flag derived from `composition.modelManager.installedURL() != nil`. While false, show `ModelSetupScene`
- [x] Plumb a per-launch network reachability check that surfaces a clear error message ("No internet — required for one-time setup") when the user is offline
- [x] Verify resume: kill the app mid-download (Cmd+Q), relaunch — setup screen continues from where it left off, doesn't restart at 0 %
- [x] Verify success: after first install completes, relaunching the app skips the setup screen entirely
- [x] Add `Apps/MacApp/Tests/` snapshot tests for the three states (in-progress, error, idle-before-start) in dark and light themes (note pre-existing MacAppTests issue per `NOTES.md` — at minimum verify the package builds; defer snapshot fix if it stays blocked)

### Task 5: AIPrompts — system + task prompts and structured-output schema

The two prompts that drive the thread-brief generation. Live in a
dedicated package so they can be edited / versioned / localised
separately from inference code.

- [x] Add `Packages/AI/AIPrompts/Sources/AIPrompts/ThreadBriefPrompt.swift`
- [x] Public `enum ThreadBriefPrompt` with `static let systemPrompt: String` and `static func taskPrompt(for input: AIThreadInput) -> String`
- [x] System prompt: terse, ≤ 150 tokens, instructs the model to (1) read all messages plus attachment metadata, (2) emit ONLY a JSON object matching the schema, (3) never invent senders / dates / amounts, (4) leave fields as JSON `null` when the source doesn't support a confident value, (5) confidence between 0 and 1 representing the model's own self-estimate
- [x] Task prompt: renders the thread as a structured block — sender / timestamp / body — then a list of attachment names + page counts (no bytes), then the JSON schema and the instruction "Reply with the JSON object only"
- [x] Add a `Packages/AI/AIPrompts/Sources/AIPrompts/StructuredOutput.swift` with the JSON schema constant + a strict parser that decodes the model output (or throws `AIError.invalidStructuredOutput` with the raw output truncated for diagnostics)
- [x] Add fixtures of expected JSON outputs in `Tests/AIPromptsTests/Fixtures/` (no real PII; reuse anonymised data from `DevSeeder.swift`)
- [x] Add tests: parser accepts every fixture, rejects malformed JSON, rejects schema violations (extra fields, wrong types), correctly maps `null` → Swift `nil`
- [x] Run `cd Packages/AI/AIPrompts && swift test`

### Task 6: MLXBackend — real Gemma 4 inference

The implementation. Loads the model from `ModelManager.installedURL()`,
runs MLX inference with the system + task prompts from Task 5, returns
parsed `AIThreadBrief`. Long-running, cancellable, single-threaded per
request (queue if multiple thread briefs are requested concurrently).

- [ ] Add `Packages/AI/AIRuntime/Sources/AIRuntime/MLXBackend.swift` conforming to `AIKit.AIService`
- [ ] Constructor takes a `ModelManager` and resolves model path eagerly; throws `AIError.modelNotInstalled` if not present
- [ ] Lazy-load the MLX model and tokeniser on first `threadBrief` call; cache for the lifetime of the backend
- [ ] Single-flight queue: serialize concurrent `threadBrief` calls so we never run two inferences at once (MLX state is not safe for concurrent decoding)
- [ ] Cancellation: each call is a `Task` honouring `Task.checkCancellation()` between every decoded token. UI tearing down the brief request cancels in flight
- [ ] Stream tokens internally (so we can implement progressive UI later) but return only when the full JSON object is decoded and parsed
- [ ] Max output tokens: cap at 512 for thread brief; trim and retry once if the model returns more without closing the JSON object
- [ ] Performance: log p50/p95 latency per call to a non-content metric collector (only counts and durations; no inputs or outputs)
- [ ] Unit tests in `Tests/AIRuntimeTests/MLXBackendTests.swift`: cannot run live MLX in CI without GPU — instead, abstract the MLX inference behind an internal protocol `LLMRunner` that `MLXBackend` uses. Test `MLXBackend` against a `FakeLLMRunner` that returns canned token streams; the real `LLMRunner` impl is a thin adapter over MLX. Tests cover: happy path, cancellation, malformed output → retry, retry exhaustion → `AIError.invalidStructuredOutput`
- [ ] Run `cd Packages/AI/AIRuntime && swift test`

### Task 7: AIKit.threadBrief() public API + wire CompositionRoot

The thin public surface feature code consumes. Wires the MLX backend
in the composition root so the rest of the app doesn't need to know
which backend runs.

- [ ] Add `Packages/AI/AIKit/Sources/AIKit/ThreadBriefService.swift` with a default implementation of `AIService.threadBrief(_:)` that just delegates to the injected backend — keep the indirection for future routing (FoundationModels fallback, llama.cpp escape hatch)
- [ ] Add a builder `static func live(modelManager: ModelManager) -> any AIService` returning an `MLXBackend`-backed service
- [ ] In `Apps/MacApp/Sources/CompositionRoot.swift`, instantiate the `ModelManager` and the `AIService` and expose `let aiService: any AIService`
- [ ] Update `Apps/MacApp/Sources/CompositionRoot.swift` to pass the `AIService` into `BriefStore`'s init
- [ ] Add `cd Packages/AI/AIKit && swift test` for the service-builder happy path (using `MockAIService`)
- [ ] Run all validation commands

### Task 8: Wire BriefStore to real AI; remove hardcoded stubs

The actual swap. `BriefStore` now loads real thread content from the DB
(by `threadID` + the active account's `accountID`), feeds it to
`AIService.threadBrief(_:)`, and publishes the result.

- [ ] In `Packages/Features/BriefFeature/Sources/BriefFeature/BriefStore.swift`, add `init(aiService: any AIService, db: AppDatabase)` (keep a parameter-less `init` only for previews / snapshot tests)
- [ ] `loadBrief(forThreadID:)` becomes: fetch `MessageRecord`s + `AttachmentRecord`s from the DB on `@DatabaseActor`, map to `AIThreadInput`, `Task { let brief = try await aiService.threadBrief(input); await MainActor.run { self.brief = ThreadBriefViewData(from: brief) } }`
- [ ] Cache successful briefs in-memory keyed by `(threadID, latest messageID)` so flipping between threads doesn't re-run inference
- [ ] Loading state: while inference is in flight, `BriefStore.isLoading == true` so `BriefRail` can show a shimmer / "Thinking…" eyebrow
- [ ] Error state: `AIError` surfaces as `BriefStore.error` and `BriefRail` shows a small "Brief generation failed · Retry" row
- [ ] Remove the entire `if threadID.hasSuffix("t1")` / `t2` block. Delete the `// TODO(§15-step-4)` comment(s) in this file
- [ ] Update `BriefRail.swift` to render the loading state (mono eyebrow "Thinking locally · 1.2s") and the error state. Don't introduce new design tokens — reuse `Color.rbFg3` for muted text and `Color.rbSignalLocalAi` for the eyebrow
- [ ] Update `Packages/Features/BriefFeature/Tests/BriefFeatureTests/BriefStoreTests.swift` to test against a `MockAIService` that returns canned `AIThreadBrief`s. Add: happy path, AI error → error state, cancellation when user switches threads mid-inference, cache hit on repeat select
- [ ] Run `cd Packages/Features/BriefFeature && swift test`

### Task 9: AIEvals — offline harness against the demo corpus

A CLI test target that runs the live `MLXBackend` against the 7 DevSeeder
threads + 20 additional synthetic but non-PII threads, and produces a
markdown report with p50 / p95 latency, faithfulness, hallucination
rate, schema validity. This is the calibration tool we use to tune
prompts and confirm we haven't regressed.

- [ ] Add `Packages/AI/AIEvals/Sources/AIEvals/EvalCorpus.swift` with 20 synthetic threads covering: short informational, single-action request, multi-message contract negotiation, attachment-heavy, calendar invite, recruiting digest, financial / invoice. Reuse the DevSeeder shapes
- [ ] Add `Packages/AI/AIEvals/Sources/AIEvals/EvalRunner.swift` exposing `func run(corpus: [AIThreadInput], service: any AIService) async throws -> EvalReport`
- [ ] Add `Packages/AI/AIEvals/Sources/AIEvals/Metrics.swift`:
    - Faithfulness heuristic: every quoted entity (sender / date / dollar amount) appears verbatim in the source thread
    - Hallucination rate: fraction of `evidence` array entries that don't correspond to a real `MessageRecord.id` or attachment filename in the input
    - Schema validity: rate of successful JSON parses
- [ ] Add a CLI entry point `Tools/EvalRunner/main.swift` (new SPM executable in the existing Tools tree if present; otherwise just a `swift run` target) that prints the markdown report to stdout
- [ ] Run the eval against the DevSeeder threads after Task 6 lands; commit the resulting report as `docs/eval-reports/step4-baseline.md`
- [ ] Unit tests for the metrics (no live MLX): `MetricsTests` verifying each metric with hand-crafted inputs
- [ ] Run `cd Packages/AI/AIEvals && swift test`

### Task 10: Performance + privacy verification

The two gates that prevent regressions. Performance via the eval
runner's measured latency; privacy via grep + a runtime network
check.

- [ ] Confirm `step4-baseline.md` report shows p50 ≤ 2.5 s and p95 ≤ 5.0 s. If not, profile (Instruments → Time Profiler on `MLXBackend.threadBrief`) and tune: reduce max tokens, shrink context window, switch to a smaller Gemma quant if necessary
- [ ] Add a network-allowlist test in `Packages/AI/AIRuntime/Tests/AIRuntimeTests/NetworkIsolationTests.swift` that uses a `URLProtocol` registered for `*` and asserts no `URLSession.shared` activity from `MLXBackend.threadBrief()` (`URLProtocol.startLoading` is never called)
- [ ] Re-run the step-3 privacy grep gate over `Apps` and `Packages` excluding `Tests`/`.build`. Zero `(Subject:|Bearer |refresh_token)` hits
- [ ] Add a stricter content-leak grep: `! grep -rnE '(os_log|Logger|print|debugPrint)\(.*(subject|body|snippet|fromAddr|toAddr|message_id_header)' Apps Packages --include='*.swift' --exclude-dir=Tests --exclude-dir=.build`. Zero hits

### Task 11: Documentation and final gate

Update `NOTES.md`, the design doc, and run all validation commands.

- [ ] Update `NOTES.md`: replace the "Why MLX is not yet linked" section with a new "On-device AI runtime" section documenting the install location (`~/Library/Application Support/PrivateAIMail/models/gemma-4-it-4bit/`), the model spec source, how to wipe (delete the dir → relaunch triggers re-download), and the eval report location
- [ ] In `/Users/alexeykhaynovsky/Documents/Projects/EMAIL_ALF/14_macos_app_design.md` §15, mark step 4 ✅ done with commit hash and brief deliverables. Note the inversion: step 4 used MLX (was originally planned for step 6). Step 6 (was MLX) is now "FoundationModelsBackend as optional secondary path" and stays ⏭️
- [ ] Run every command in `## Validation Commands` above. Every one exits 0
- [ ] Final manual smoke: delete `~/Library/Application Support/PrivateAIMail/`, launch the app, watch the setup screen, wait for download to complete, click on a DevSeeder thread (`demo-t3` Lease addendum — informational, no brief in the previous hardcoded stubs), confirm the Brief Rail populates with a real AI-generated brief within ~3 seconds. Repeat for `demo-t1` (Acme contract — should yield a deadline-bearing brief). Repeat for `demo-t6` (Notion digest — should yield empty-state-ish brief with low confidence)
- [ ] Tag the merge commit `step4-complete` and post the eval report path in the merge commit message
