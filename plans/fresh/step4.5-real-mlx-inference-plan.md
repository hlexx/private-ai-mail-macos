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
[`mlx-community/gemma-4-e4b-it-OptiQ-4bit`](https://hf.co/mlx-community/gemma-4-e4b-it-OptiQ-4bit):

- **7.52 B parameters**, mixed-precision OptiQ quantisation (155
  sensitive layers at 8-bit, 224 robust layers at 4-bit — per-layer
  bit-widths chosen by KL-divergence sensitivity analysis)
- Tagged `apple-silicon` — explicitly tuned for M-series; OptiQ
  toolkit is from mlx-optiq.com
- License: `gemma` (Google Gemma Terms of Use — commercial use
  allowed, with standard responsible-use clauses)
- ~6.57 GB on disk (two safetensors shards: 3.52 GB + 3.01 GB) plus
  config / tokenizer (~30 MB)
- `optiq_metadata.json` is the only non-standard file; both `mlx-lm`
  (Python) and `mlx-swift-examples` (`MLXLLM` Swift module) handle it
  transparently — no custom loader needed
- gemma4 architecture, supported by MLXLLM out of the box
- Released by mlx-community on 11 Apr 2026, updated 10 May 2026,
  11K+ downloads (smaller community than the vanilla quants but
  validated; **note size**: every other gemma-4-e4b-it variant ships
  at ~1.2 GB, so the OptiQ version is intentionally a quality-over-
  size trade-off)

After step 4.5 the `AIEvals` baseline report contains real latency and
real faithfulness numbers, the manual smoke test (open demo-t1 → see
populated Brief Rail in single-digit seconds) works, and the privacy
network-isolation test stays green because all inference is on-device.

### Trade-offs we accept by picking OptiQ

- **First-launch download is ~6.6 GB**, not ~1.2 GB. On a 100 Mbps
  home connection that's ~9 min; on flaky mobile-tether it's an hour
  plus. ModelSetupScene (already shipped in step 4) has the
  progress-bar + resume affordance; we don't change UX, just message
  the size in the empty-state copy.
- **Latency is higher than a 1.67 B model**. Realistic on M-series:
  p50 in the 5–10 s range, p95 ≤ 15 s for a 256-token brief. See
  success criteria below; budgets are calibrated for OptiQ, not for
  the smaller quant.
- **Disk pressure**: the user's `~/Library/Application Support/
  PrivateAIMail/models/` directory carries ~6.6 GB after first launch.
  This is the largest single thing the app owns; Settings → AI should
  surface it and provide an "Uninstall model" action (out of scope
  for step 4.5 but flagged for a follow-up).

### Fallback path if OptiQ doesn't hit budget

If `AIEvals` reports p95 > 20 s on a target M-series machine (or any
other blocking quality regression), fall back to
[`mlx-community/gemma-4-e2b-it-4bit`](https://hf.co/mlx-community/gemma-4-e2b-it-4bit)
(1.21 B params, Apache 2.0, ~700 MB on disk, 313K+ downloads). The
fallback is just a `GemmaModelSpec` swap — no architectural change.
Document the decision in `docs/eval-reports/`.

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

- `MLXLLMRunner.load(from:)` loads `gemma-4-e4b-it-OptiQ-4bit` from
  `~/Library/Application Support/PrivateAIMail/models/gemma-4-it-optiq-4bit/`
  using `MLXLLM.LLMModelFactory` (or equivalent — verify exact API at
  execution time), caches the `ModelContainer` in-process, completes
  in **≤ 30 s on M-series cold start** (model is 6.6 GB, loaded into
  unified memory).
- `MLXLLMRunner.generate(...)` runs real autoregressive decoding via
  MLX, honours `Task.checkCancellation()` between tokens, calls the
  `onToken` callback for each decoded token, caps at `maxTokens`,
  returns the full decoded string.
- A brand-new manual smoke run: wipe sandbox container + DB, launch
  the app, complete the first-launch model download, click demo-t1 in
  the inbox, see the AI Brief Rail populate with a real model output
  within **≤ 20 s p95 on M-series** (allows 1 cold load + 1
  generation). Subsequent thread clicks ≤ 10 s p95 (cached model).
- `AIEvals` baseline report shows real numbers (calibrated for OptiQ
  7.5 B):
    - p50 latency in `[3 s … 10 s]` range
    - p95 latency ≤ 15 s
    - Schema validity ≥ 95 % (some sampling-randomness tolerated)
    - Faithfulness (heuristic) ≥ 0.85
    - Hallucination rate < 5 %

If real numbers blow past these by > 2× on the dev machine, treat it
as a signal to drop to the `gemma-4-e2b-it-4bit` fallback per the
trade-off note above — don't ship a 30-second-per-brief experience.
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

- [x] In `Packages/AI/AIRuntime/Package.swift`, add `.package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main")` (corrected: MLXLLM lives in mlx-swift-lm, not mlx-swift-examples). Pin to a specific commit hash after Task 6 stabilises (don't keep `branch: "main"` long-term — capture the resolved commit and rewrite as `revision:`)
- [x] Add the target dependency: `.product(name: "MLXLLM", package: "mlx-swift-lm")` and `.product(name: "MLXLMCommon", package: "mlx-swift-lm")`
- [x] Run `tuist generate --no-open` so the SPM graph picks up the new dep
- [x] Run `cd Packages/AI/AIRuntime && swift build` and confirm both new modules resolve and compile

### Task 2: Update GemmaModelSpec to match gemma-4-e4b-it-4bit

The `ModelManager` consults a `GemmaModelSpec` constant (file list +
SHA-256 + total bytes). The step 4 baseline pinned placeholder values
because the runner wasn't real. Update to the actual repo on
HuggingFace.

- [x] Open `Packages/AI/AIRuntime/Sources/AIRuntime/GemmaModelSpec.swift`
- [x] Set `repoID = "mlx-community/gemma-4-e4b-it-OptiQ-4bit"`
- [x] Rename the on-disk install directory to `gemma-4-it-optiq-4bit` (so a previous install of the smaller variant doesn't get confused with this one). Update every literal path string in `AIRuntime` and `ModelSetupScene` that referenced `gemma-4-it-4bit`
- [x] Set `revision` to the latest commit hash at execution time (lookup via `https://huggingface.co/api/models/mlx-community/gemma-4-e4b-it-OptiQ-4bit` `sha` field). Pin to a specific commit, do NOT leave as `"main"`
- [x] Build the `files: [GemmaModelFile]` array from the actual tree. The known file set (from the HF tree API as of the plan-writing moment):
    - `config.json` (~82 KB)
    - `chat_template.jinja` (~17 KB)
    - `generation_config.json` (~208 B)
    - `model-00001-of-00002.safetensors` (~3.52 GB)
    - `model-00002-of-00002.safetensors` (~3.01 GB)
    - `model.safetensors.index.json` (~151 KB)
    - `optiq_metadata.json` (~40 KB) — keep this one; the loader looks for it
    - `tokenizer.json` (~32 MB)
    - `tokenizer_config.json` (~3 KB)
    - `README.md` and `.gitattributes` — skip (not needed at runtime)
- [x] Each `GemmaModelFile` has `name`, `expectedSHA256`, `expectedBytes`. Capture SHA-256 from each file's `lfs.sha256` field on the HF tree API; for non-LFS small files, hash by streaming the response body during the first successful download and pin the captured value
- [x] Compute and set `totalBytes` (~6.57 GB)
- [x] Set the download URL template: `https://huggingface.co/{repoID}/resolve/{revision}/{fileName}`
- [x] Run `cd Packages/AI/AIRuntime && swift test` — `ModelManagerTests` should still pass (it uses a `FakeURLProtocol` and an in-test spec, not the real one)
- [x] Manual: `rm -rf ~/Library/Application Support/PrivateAIMail/models/`, launch the app, watch ModelSetupScene download the real ~6.57 GB. Note the user-visible duration in the manual smoke notes. Confirm SHA-verify passes on every file
- [x] Update the empty-state copy in ModelSetupScene to mention ~6.5 GB (currently the screen probably says "~2 GB"). Honest sizes help users not abandon the download

### Task 3: Implement MLXLLMRunner.load — real model loading via MLXLLM

Replace the stub `load()` with code that loads the gemma-4 model and
tokeniser from disk using `MLXLLM`'s factory APIs.

- [x] Open `Packages/AI/AIRuntime/Sources/AIRuntime/MLXLLMRunner.swift`
- [x] Import `MLXLLM` and `MLXLMCommon`
- [x] Add private state: `private var modelContainer: ModelContainer?` (type from MLXLMCommon)
- [x] Rewrite `load(from modelDirectory: URL)`:
    - `let factory = LLMModelFactory.shared`
    - `let configuration = ModelConfiguration(directory: modelDirectory)`
    - `let container = try await factory.loadContainer(configuration: configuration)`
    - Store `container` in `self.modelContainer`
    - Set `isLoaded = true`
- [x] Keep the `NSLock` for the `isLoaded` flag, but mark the function `async` and avoid locking across `await` (use the lock only for setter, the actor or main-actor isolation if needed)
- [x] Handle errors: catch and rethrow as `MLXLLMRunnerError.weightLoadFailed(String(describing: error))` (add this new case to the enum)
- [x] Update `MLXLLMRunnerError` to include `.weightLoadFailed(String)` and `.tokeniserMissing` cases
- [x] Run `cd Packages/AI/AIRuntime && swift build` to confirm types match. Fix `LLMModelFactory` / `ModelConfiguration` API surface if mlx-swift-examples API differs from this checkbox text (check their README — the API has changed across releases). The Hugging Face model card for gemma-4-e4b-it-4bit links to an mlx-swift example script that shows the exact loader sequence; mirror it

### Task 4: Implement MLXLLMRunner.generate — real autoregressive decoding

Replace the stub `generate()` with real token-by-token generation.

- [x] In `MLXLLMRunner.generate(systemPrompt:userPrompt:maxTokens:onToken:)`:
    - Guard `modelContainer != nil`, else throw `.modelNotLoaded`
    - Build the chat-template prompt. Gemma 4 uses Gemma's chat template: `<start_of_turn>user\n{system}\n\n{user}<end_of_turn>\n<start_of_turn>model\n`. Use `tokenizer.applyChatTemplate(...)` if MLXLMCommon exposes it; otherwise format the string manually and tokenise
    - Use `modelContainer.perform { context in ... }` (the lock-style API of MLXLMCommon) to run a `generate(...)` call with `GenerateParameters(temperature: 0.2, topP: 0.9, maxTokens: maxTokens)` — temperature low because we want structured JSON output, not creativity
    - Stream tokens: for each new token decoded, call `onToken(decodedString)`
    - Between every token, call `try Task.checkCancellation()`. If cancelled, return what we have or rethrow `AIError.cancelled` (let `MLXBackend` map it)
    - Stop early if the model emits the end-of-turn token before `maxTokens`
    - Return the full decoded string (concatenated, no system/user prefix)
- [x] Stricter token bound: cap at `min(maxTokens, 512)` for thread brief — keeps p95 latency manageable
- [x] If the model produces output not matching JSON schema (no `{` after some threshold), abort and let `MLXBackend` retry once — the retry already exists in step 4's `MLXBackend.threadBrief`
- [x] Remove the `throw MLXLLMRunnerError.notImplemented` line. The enum case stays for backwards compatibility but is unreachable

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
- [ ] Inspect the report. Confirm (calibrated for OptiQ 7.5 B):
    - All 20 corpus entries pass schema validity (≥ 95 % allowing
      sampling jitter; aim for 100 %)
    - p50 latency in `[3 s … 10 s]` range
    - p95 latency ≤ 15 s
    - Faithfulness ≥ 0.85
    - Hallucination rate < 5 %
- [ ] If any of those miss, tune the prompt in `Packages/AI/AIPrompts/Sources/AIPrompts/ThreadBriefPrompt.swift`: tighter instructions, fewer evidence-array slots, smaller max-token cap, lower temperature. Re-run eval. Iterate up to 3 times
- [ ] If after tuning p95 is still > 20 s (or any other quality budget is missed by > 2×), execute the documented fallback: change the `repoID` in `GemmaModelSpec` to `mlx-community/gemma-4-e2b-it-4bit` (1.21 B params, Apache 2.0, ~700 MB on disk), update file list / SHA / totalBytes, re-download, re-eval. Capture the decision and the comparison numbers in `docs/eval-reports/step4.5-model-selection.md`
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
- [ ] Manual smoke from a clean state: `pkill -9 -f PrivateAIMail; rm -rf ~/Library/Application\ Support/PrivateAIMail/; open /path/to/PrivateAIMail.app`. Watch ModelSetupScene download the full ~6.57 GB (record duration as part of the QA notes). Click demo-t1. AI Brief Rail populates with a real model output in < 20 s (first generation includes cold load; subsequent ones < 10 s). Click demo-t3 (informational) — brief is generated but may have `nil` request/deadline (model decides). Click demo-t6 (Notion digest) — same
- [ ] Update `NOTES.md` "On-device AI runtime" section: confirm the model is loaded for real, point at the new baseline report, mention how to wipe weights for re-download
- [ ] In `EMAIL_ALF/14_macos_app_design.md` §15 step 4 line, mark as **truly ✅ done** with both branch + commit hash for step 4 _and_ step 4.5. Note inversion (MLX-first, FoundationModels later) is locked in
- [ ] Tag the final commit `step4-real-mlx-complete` (this will be the merge point with `main`)
- [ ] Worktree cleanup left to the human merging
