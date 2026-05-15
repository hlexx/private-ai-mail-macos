# Step 4.5: Real MLX Inference — Wire mlx-swift-examples + Gemma 4 E4B 4-bit

## Overview

Step 4 (commit range `9a2b546..d689f2e` on branch
`step4-mlx-gemma-thread-brief-plan`) built every layer of the AI stack —
`AIService` protocol, `ModelManager` with resumable downloads,
`ModelSetupScene`, `AIPrompts`, `MLXBackend` actor, `BriefStore` wiring,
`AIEvals` harness, mlx-swift dep, Metal Toolchain in CI — except the
one thing that actually generates text. `Packages/AI/AIRuntime/Sources/AIRuntime/MLXLLMRunner.swift`
is a stub: `load()` just flips a bool, `generate()` immediately throws
`MLXLLMRunnerError.notImplemented`. Hence `AIEvals` reports `0.00 s p50`
and `1.000 faithfulness` — those are mock metrics. If we merged step 4
into `main` as-is, every brief request would surface "Brief generation
failed", regressing the demo (which currently shows hardcoded stubs for
demo-t1 / demo-t2).

Step 4.5 replaces that stub with **real on-device generation** using
[mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)
`MLXLLM`, loading
[`mlx-community/gemma-4-e4b-it-4bit`](https://hf.co/mlx-community/gemma-4-e4b-it-4bit):

- 1.67 B parameters, 4-bit quantised
- Apache 2.0 — clean for commercial product
- ~1.0–1.5 GB on disk
- gemma4 architecture, supported by MLXLLM out of the box
- Released by mlx-community on 2 Apr 2026, updated 13 Apr 2026, 79.5K+
  downloads (community-validated)

After step 4.5 the `AIEvals` baseline report contains real latency and
real faithfulness numbers, the manual smoke test (open demo-t1 → see
populated Brief Rail in < 5 s) works, and the privacy network-isolation
test stays green because all inference is on-device.

## Context

- Branch `step4-mlx-gemma-thread-brief-plan` is the working branch.
  **Do NOT branch off `main`** for this plan — it has to merge in
  atomically with step 4 to avoid the regression described above.
- The stub lives at
  `Packages/AI/AIRuntime/Sources/AIRuntime/MLXLLMRunner.swift`. Replace
  the body, keep the public surface (it conforms to
  `LLMRunner` defined in `LLMRunner.swift`).
- `MLXBackend.swift` already wires `LLMRunner` through a single-flight
  queue, calls `runner.load(from:)` on first use, calls
  `runner.generate(systemPrompt:userPrompt:maxTokens:onToken:)` for
  each request, and converts errors to `AIError`. Don't change that.
- `ModelManager` already downloads from a `GemmaModelSpec` constant.
  That spec needs to be updated to the real file list and SHA-256
  digests of `gemma-4-e4b-it-4bit` shards.
- mlx-swift is already a dependency of `AIRuntime` (added in step 4
  Task 1). mlx-swift-examples is a separate package and must be added
  here.
- Metal Toolchain is already wired in CI (step 4 Task 1). CI runners
  still won't run real MLX inference (no GPU); we keep the test
  pyramid strict (unit tests use `FakeLLMRunner`, integration tests
  run only locally and are gated by an environment flag).
- Tests added in step 4 must keep passing after this step. Specifically:
  `AIRuntimeTests`, `AIKitTests`, `BriefFeatureTests`. They all use
  `MockAIService` or `FakeLLMRunner`, so they are unaffected by the
  real implementation.

## Success Criteria

- `MLXLLMRunner.load(from:)` loads
  `gemma-4-e4b-it-4bit` from `~/Library/Application Support/PrivateAIMail/models/gemma-4-it-4bit/`
  using `MLXLLM.LLMModelFactory` or equivalent, caches the model
  in-process, completes in ≤ 15 s on M-series cold start.
- `MLXLLMRunner.generate(...)` runs real autoregressive decoding via
  MLX, honours `Task.checkCancellation()` between tokens, calls the
  `onToken` callback for each decoded token, caps at `maxTokens`,
  returns the full decoded string.
- A brand-new manual smoke run: wipe sandbox container + DB, launch
  the app, complete the first-launch model download, click demo-t1 in
  the inbox, see the AI Brief Rail populate with a real model output
  within **≤ 8 s p95 on M-series** (allows 1 cold load + 1 generation).
  Subsequent thread clicks ≤ 3 s p95 (cached model).
- `AIEvals` baseline report shows real numbers:
    - p50 latency in `[0.8 s … 2.5 s]` range (suspicious if outside)
    - p95 latency ≤ 5.0 s
    - Schema validity ≥ 95 % (some sampling-randomness tolerated)
    - Faithfulness (heuristic) ≥ 0.85
    - Hallucination rate < 5 %
- `docs/eval-reports/step4-baseline.md` regenerated with the real
  numbers and committed.
- The previous `MLXLLMRunnerError.notImplemented` case stays in the
  enum but is unreachable. New error cases added as needed:
  `.tokeniserMissing`, `.weightLoadFailed(String)`.
- `xcodebuild build -scheme MacApp` ends with `** BUILD SUCCEEDED **`.
- `swiftlint --strict` reports 0 violations.
- All per-package `swift test` runs exit 0. New tests:
    - `MLXLLMRunnerTests.swift` (skipped on CI via
      `ProcessInfo.processInfo.environment["RB_RUN_REAL_MLX_TESTS"] == "1"`)
      that loads the real model and runs a 16-token generation against
      a fixed prompt, asserting non-empty output.
- Network privacy gate intact: zero `URLSession` activity from
  `MLXBackend.threadBrief()` once weights are downloaded. The existing
  `NetworkIsolationTests` snapshot test still passes.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && git checkout step4-mlx-gemma-thread-brief-plan`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && tuist generate --no-open`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && swiftlint --strict`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/AI/AIRuntime && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/AI/AIKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/Features/BriefFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos/Packages/AI/AIEvals && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/private-ai-mail-macos && ! grep -nE 'notImplemented|TODO.*MLX|placeholder.*MLX' Packages/AI/AIRuntime/Sources --include='*.swift'`

### Task 1: Add mlx-swift-examples dependency to AIRuntime

`mlx-swift-examples` ships the `MLXLLM` module which already implements
the gemma4 architecture with weight loading, tokenization, and
generation utilities. Add it to AIRuntime so we can drop the stub.

- [ ] In `Packages/AI/AIRuntime/Package.swift`, add `.package(url: "https://github.com/ml-explore/mlx-swift-examples.git", branch: "main")`. Pin to a specific commit hash after Task 6 stabilises (don't keep `branch: "main"` long-term — capture the resolved commit and rewrite as `revision:`)
- [ ] Add the target dependency: `.product(name: "MLXLLM", package: "mlx-swift-examples")` and `.product(name: "MLXLMCommon", package: "mlx-swift-examples")`
- [ ] Run `tuist generate --no-open` so the SPM graph picks up the new dep
- [ ] Run `cd Packages/AI/AIRuntime && swift build` and confirm both new modules resolve and compile

### Task 2: Update GemmaModelSpec to match gemma-4-e4b-it-4bit

The `ModelManager` consults a `GemmaModelSpec` constant (file list +
SHA-256 + total bytes). The step 4 baseline pinned placeholder values
because the runner wasn't real. Update to the actual repo on
HuggingFace.

- [ ] Open `Packages/AI/AIRuntime/Sources/AIRuntime/GemmaModelSpec.swift`
- [ ] Set `repoID = "mlx-community/gemma-4-e4b-it-4bit"`
- [ ] Set `revision` to the latest commit hash at execution time (lookup via `https://huggingface.co/api/models/mlx-community/gemma-4-e4b-it-4bit` `sha` field)
- [ ] Build the `files: [GemmaModelFile]` array. Each `GemmaModelFile` has `name`, `expectedSHA256`, `expectedBytes`. Required files for MLX gemma4: `config.json`, `tokenizer.json`, `tokenizer_config.json`, `special_tokens_map.json`, plus the `*.safetensors` shards (typically `model.safetensors` or `model-00001-of-N.safetensors`). Get the file list from `https://huggingface.co/api/models/mlx-community/gemma-4-e4b-it-4bit/tree/main`. Capture SHA-256 from each file's `lfs.sha256` field (or compute by streaming)
- [ ] Compute and set `totalBytes` (sum of file `size` fields from the API response)
- [ ] Set the download URL template: `https://huggingface.co/{repoID}/resolve/{revision}/{fileName}`
- [ ] Run `cd Packages/AI/AIRuntime && swift test` — `ModelManagerTests` should still pass (it uses a `FakeURLProtocol` and an in-test spec, not the real one)
- [ ] Manual: `rm -rf ~/Library/Application Support/PrivateAIMail/models/`, launch the app, watch ModelSetupScene download the real ~1.2 GB. Confirm SHA-verify passes on every file

### Task 3: Implement MLXLLMRunner.load — real model loading via MLXLLM

Replace the stub `load()` with code that loads the gemma-4 model and
tokeniser from disk using `MLXLLM`'s factory APIs.

- [ ] Open `Packages/AI/AIRuntime/Sources/AIRuntime/MLXLLMRunner.swift`
- [ ] Import `MLXLLM` and `MLXLMCommon`
- [ ] Add private state: `private var modelContainer: ModelContainer?` (type from MLXLMCommon)
- [ ] Rewrite `load(from modelDirectory: URL)`:
    - `let factory = LLMModelFactory.shared`
    - `let configuration = ModelConfiguration(directory: modelDirectory)`
    - `let container = try await factory.loadContainer(configuration: configuration)`
    - Store `container` in `self.modelContainer`
    - Set `isLoaded = true`
- [ ] Keep the `NSLock` for the `isLoaded` flag, but mark the function `async` and avoid locking across `await` (use the lock only for setter, the actor or main-actor isolation if needed)
- [ ] Handle errors: catch and rethrow as `MLXLLMRunnerError.weightLoadFailed(String(describing: error))` (add this new case to the enum)
- [ ] Update `MLXLLMRunnerError` to include `.weightLoadFailed(String)` and `.tokeniserMissing` cases
- [ ] Run `cd Packages/AI/AIRuntime && swift build` to confirm types match. Fix `LLMModelFactory` / `ModelConfiguration` API surface if mlx-swift-examples API differs from this checkbox text (check their README — the API has changed across releases). The Hugging Face model card for gemma-4-e4b-it-4bit links to an mlx-swift example script that shows the exact loader sequence; mirror it

### Task 4: Implement MLXLLMRunner.generate — real autoregressive decoding

Replace the stub `generate()` with real token-by-token generation.

- [ ] In `MLXLLMRunner.generate(systemPrompt:userPrompt:maxTokens:onToken:)`:
    - Guard `modelContainer != nil`, else throw `.modelNotLoaded`
    - Build the chat-template prompt. Gemma 4 uses Gemma's chat template: `<start_of_turn>user\n{system}\n\n{user}<end_of_turn>\n<start_of_turn>model\n`. Use `tokenizer.applyChatTemplate(...)` if MLXLMCommon exposes it; otherwise format the string manually and tokenise
    - Use `modelContainer.perform { context in ... }` (the lock-style API of MLXLMCommon) to run a `generate(...)` call with `GenerateParameters(temperature: 0.2, topP: 0.9, maxTokens: maxTokens)` — temperature low because we want structured JSON output, not creativity
    - Stream tokens: for each new token decoded, call `onToken(decodedString)`
    - Between every token, call `try Task.checkCancellation()`. If cancelled, return what we have or rethrow `AIError.cancelled` (let `MLXBackend` map it)
    - Stop early if the model emits the end-of-turn token before `maxTokens`
    - Return the full decoded string (concatenated, no system/user prefix)
- [ ] Stricter token bound: cap at `min(maxTokens, 512)` for thread brief — keeps p95 latency manageable
- [ ] If the model produces output not matching JSON schema (no `{` after some threshold), abort and let `MLXBackend` retry once — the retry already exists in step 4's `MLXBackend.threadBrief`
- [ ] Remove the `throw MLXLLMRunnerError.notImplemented` line. The enum case stays for backwards compatibility but is unreachable

### Task 5: Tighten MLXBackend to surface real latency

`MLXBackend` already collects timing metrics; with a real LLM behind
it, we want accurate p50/p95 plumbed through the eval pipeline.

- [ ] In `Packages/AI/AIRuntime/Sources/AIRuntime/MLXBackend.swift`, ensure each `threadBrief(_:)` call records start/end timestamps and exposes them via the existing `LatencySample` (or equivalent) hook the `AIEvals` runner reads
- [ ] If the existing impl just logs durations to stderr, add a `Sendable` `LatencyRecorder` protocol that `AIEvals.EvalRunner` can plug into
- [ ] Run `cd Packages/AI/AIRuntime && swift test` — keep all `MLXBackendTests` (which use `FakeLLMRunner`) passing

### Task 6: Real eval baseline + commit report

Now that inference is real, regenerate the baseline report against the
real `MLXBackend`-backed `AIService`. This is the calibration step.

- [ ] Ensure `~/Library/Application Support/PrivateAIMail/models/gemma-4-it-4bit/` is populated (run the app once and let the first-launch flow download)
- [ ] Run the eval CLI: `cd Packages/AI/AIEvals && swift run EvalRunner > docs/eval-reports/step4-baseline.md` (or whatever the entry-point is — verify Tools tree)
- [ ] Inspect the report. Confirm:
    - All 20 corpus entries pass schema validity
    - p50 latency is non-zero and < 2.5 s
    - p95 < 5.0 s
    - Faithfulness ≥ 0.85
    - Hallucination rate < 5 %
- [ ] If any of those miss, tune the prompt in `Packages/AI/AIPrompts/Sources/AIPrompts/ThreadBriefPrompt.swift`: tighter instructions, fewer evidence-array slots, smaller max-token cap, lower temperature. Re-run eval. Iterate up to 3 times; if still failing, fall back to `gemma-4-e2b-it-4bit` (1.21 B params) and re-eval
- [ ] Commit the regenerated `docs/eval-reports/step4-baseline.md` with the real numbers
- [ ] In `docs/eval-reports/`, add `step4-prompt-notes.md` if you ended up tuning the prompt — record what changed and which corpus entries improved

### Task 7: Optional integration test gated by env var

A real-model integration test that only runs when explicitly opted-in,
so CI without GPU stays green.

- [ ] Add `Packages/AI/AIRuntime/Tests/AIRuntimeTests/MLXLLMRunnerLiveTests.swift`
- [ ] In `setUp`, return early (skip) unless `ProcessInfo.processInfo.environment["RB_RUN_REAL_MLX_TESTS"] == "1"` and the model directory exists at the expected path
- [ ] One test: `loadAndGenerateShortOutput()` — loads the model, generates against a fixed 1-message thread input, asserts the output starts with `{` and contains the substring `"summary"`, in < 10 s wall clock
- [ ] Locally run with `RB_RUN_REAL_MLX_TESTS=1 swift test` after Task 6 baseline lands. Commit only after this passes
- [ ] CI: leave the env unset → test auto-skips

### Task 8: Final gate + cleanup

- [ ] Re-run every command in `## Validation Commands` above. Every one exits 0
- [ ] Manual smoke from a clean state: `pkill -9 -f PrivateAIMail; rm -rf ~/Library/Application\ Support/PrivateAIMail/; open /path/to/PrivateAIMail.app`. Watch ModelSetupScene download. Click demo-t1. AI Brief Rail populates with a real model output in < 8 s. Click demo-t3 (informational) — brief is generated but may have `nil` request/deadline (model decides). Click demo-t6 (Notion digest) — same
- [ ] Update `NOTES.md` "On-device AI runtime" section: confirm the model is loaded for real, point at the new baseline report, mention how to wipe weights for re-download
- [ ] In `EMAIL_ALF/14_macos_app_design.md` §15 step 4 line, mark as **truly ✅ done** with both branch + commit hash for step 4 _and_ step 4.5. Note inversion (MLX-first, FoundationModels later) is locked in
- [ ] Tag the final commit `step4-real-mlx-complete` (this will be the merge point with `main`)
- [ ] Worktree cleanup left to the human merging
