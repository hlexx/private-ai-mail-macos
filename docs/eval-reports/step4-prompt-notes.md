# Prompt Tuning Notes

## Changes made during step 4.5

### Iteration 1: Fix hallucination rate (E4B model)

**Problem:** E4B model (7.5B) produced 32.1% hallucination rate — it was
inventing senders, dates, and facts not present in the email threads.

**Changes to `ThreadBriefPrompt.systemPrompt`:**
- Added explicit rule: "Never invent senders, dates, or amounts"
- Added rule: "Leave fields as null when the source does not support a confident value"
- Added rule: "Each evidence entry must be a short verbatim quote from the thread"
- Reduced temperature from 0.2 to 0.1 in `MLXLLMRunner`

**Result:** Hallucination rate dropped from 32.1% to 0.0%. Faithfulness
improved from 0.679 to 1.000. Schema validity remained at 100%.

### Iteration 2: Fix structured output for E2B model

**Problem:** After switching from E4B (7.5B) to E2B (1.21B) for latency,
the smaller model only achieved 20% schema validity. Two failure modes:
1. Empty output (model emits end-of-turn immediately)
2. `<|channel>thought` prefix (model enters chain-of-thought mode)

**Changes:**
1. **JSON seeding in `MLXLLMRunner`:** Changed prompt template from
   `<start_of_turn>model\n` to `<start_of_turn>model\n{` — forces the
   model to continue generating inside a JSON object.

2. **Simplified system prompt:** Replaced formal JSON schema reference with
   inline field descriptions and a concrete example JSON object. Small
   models follow examples more reliably than schema definitions.

3. **Increased maxRetries from 1 to 2** in `MLXBackend` default constructor.

**Result:** Schema validity improved from 20% to 100%. All other metrics
maintained (faithfulness 1.0, hallucination 0%).

## Current prompt text

## Registry contract update

The eval runner now records PromptTask metadata for each measured model task:
task id, prompt version, and schema version. The current baseline is tied to
`threadBrief` with the versions provided by `PromptTaskRegistry`.

Attachment summary evals use a synthetic local corpus with no private data.
The first release gate tracks schema validity, evidence coverage, and
hallucination rate against extracted attachment text. Every evidence item must
point back to a chunk quote instead of introducing file facts that were not in
the extracted text.

### System prompt
```
You are an email analyst. Output ONLY a JSON object -- no text before or after.
Fields: summary (string), request (string or null), deadline (string or null),
risk (string or null), nextStep (string or null), evidence (array of short quotes),
confidence (number 0-1).
Rules: never invent facts; use null when unsure; evidence must be verbatim quotes;
keep response under 200 tokens.
Example output: {"summary":"Team sync on Q3 goals","request":"Review the deck by Friday",
"deadline":"Friday","risk":null,"nextStep":"Reply with feedback",
"evidence":["Review the deck by Friday","Q3 goals"],"confidence":0.9}
```

### Generation parameters
- Temperature: 0.1
- Top-p: 0.9
- Max tokens: 256 (capped in MLXLLMRunner)
