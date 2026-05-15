# AIEvals — Thread Brief Baseline Report

**Model:** `mlx-community/gemma-4-e2b-it-4bit` (1.21B params, 4-bit quantization)
**Machine:** Apple Silicon (M-series)
**Date:** 2026-05-15

| Metric | Value |
|---|---|
| Threads evaluated | 20 |
| Successful | 20 |
| Schema validity | 100.0% |
| Mean faithfulness | 1.000 |
| Mean hallucination rate | 0.0% |
| p50 latency | 3.57s |
| p95 latency | 6.17s |

## Per-thread results

| Thread | Latency | Schema | Faithfulness | Hallucination | Error |
|---|---|---|---|---|---|
| eval-01-newsletter | 6.53s | ok | 1.000 | 0.0% |  |
| eval-02-pto-request | 2.76s | ok | 1.000 | 0.0% |  |
| eval-03-contract-negotiation | 2.20s | ok | 1.000 | 0.0% |  |
| eval-04-design-review | 2.96s | ok | 1.000 | 0.0% |  |
| eval-05-calendar-invite | 2.65s | ok | 1.000 | 0.0% |  |
| eval-06-recruiting-digest | 2.99s | ok | 1.000 | 0.0% |  |
| eval-07-invoice | 3.27s | ok | 1.000 | 0.0% |  |
| eval-08-shipping | 3.33s | ok | 1.000 | 0.0% |  |
| eval-09-security-alert | 3.39s | ok | 1.000 | 0.0% |  |
| eval-10-meeting-followup | 6.15s | ok | 1.000 | 0.0% |  |
| eval-11-support-escalation | 4.52s | ok | 1.000 | 0.0% |  |
| eval-12-travel | 4.91s | ok | 1.000 | 0.0% |  |
| eval-13-pr-review | 2.98s | ok | 1.000 | 0.0% |  |
| eval-14-subscription-renewal | 3.76s | ok | 1.000 | 0.0% |  |
| eval-15-compliance | 4.00s | ok | 1.000 | 0.0% |  |
| eval-16-onboarding | 4.21s | ok | 1.000 | 0.0% |  |
| eval-17-outage | 3.01s | ok | 1.000 | 0.0% |  |
| eval-18-event-invite | 4.65s | ok | 1.000 | 0.0% |  |
| eval-19-budget-approval | 5.61s | ok | 1.000 | 0.0% |  |
| eval-20-project-update | 5.31s | ok | 1.000 | 0.0% |  |
