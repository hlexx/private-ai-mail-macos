# Model Selection Decision Log

## Final choice: `gemma-4-e2b-it-4bit` (1.21B params)

Three models were evaluated during step 4.5. The selection was driven by the
latency budget (p50 3-10s, p95 <=15s) and structured-output reliability.

## Candidates evaluated

### 1. `mlx-community/gemma-4-e4b-it-OptiQ-4bit` (7.5B, ~6.6 GB)

- **Status:** REJECTED (loading failure)
- OptiQ per-layer mixed-precision quantization applies 4-bit to the
  `per_layer_model_projection` weight, but mlx-swift-lm's `ScaledLinear`
  module uses `let weight: MLXArray` (dense only). Loading fails with
  `mismatchedSize` for the projection layer.
- Would require custom model code changes in mlx-swift-lm to support.

### 2. `mlx-community/gemma-4-e4b-it-4bit` (7.5B, ~5.2 GB)

- **Status:** REJECTED (latency >2x over budget)
- Standard uniform 4-bit quantization. Loads and runs correctly.
- Quality results (after prompt tuning):
  - Schema validity: 100%
  - Faithfulness: 1.000
  - Hallucination rate: 0.0%
- Latency results:
  - p50: 35.83s (budget: 3-10s) -- 3.6x over
  - p95: 48.13s (budget: <=15s) -- 3.2x over
- 7.5B params is too large for single-digit-second inference on M-series
  with the 256-token budget.

### 3. `mlx-community/gemma-4-e2b-it-4bit` (1.21B, ~3.6 GB)

- **Status:** ACCEPTED
- Standard uniform 4-bit quantization. Apache 2.0 license.
- Initial run (no JSON seeding): 20% schema validity. The model emitted
  `<|channel>thought` tokens or empty output instead of JSON.
- After seeding the generation with `{` and simplifying the system prompt
  to include a concrete JSON example:
  - Schema validity: 100%
  - Faithfulness: 1.000
  - Hallucination rate: 0.0%
  - p50: 3.57s
  - p95: 6.17s
- All metrics well within budget.

## Key engineering decisions

1. **JSON seeding:** The prompt template ends with `<start_of_turn>model\n{`
   so the model's first generated token is already inside a JSON object.
   The `{` is prepended to the output string. This technique is critical
   for small models that otherwise attempt chain-of-thought reasoning.

2. **Inline JSON example in system prompt:** Replaced the formal JSON schema
   description with field descriptions + a concrete example object. Small
   models follow examples more reliably than schema specifications.

3. **maxRetries increased to 2:** The smaller model occasionally needs a
   retry; 2 retries keeps total worst-case latency under 20s.
