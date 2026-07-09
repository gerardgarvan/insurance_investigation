---
status: partial
phase: 117-make-a-lifespan-gannt-that-collapses-across-all-time-but-still-keeps-treatment-type-etc-sepearate
source: [117-VERIFICATION.md]
started: 2026-07-09
updated: 2026-07-09
---

## Current Test

[awaiting human testing on HiPerGator]

## Tests

### 1. Runtime CSV production
expected: Running `R/101_gantt_lifespan_collapse.R` on HiPerGator writes `output/gantt_lifespan.csv` with FEWER rows than `output/gantt_episodes.csv` (episodes collapsed per patient × treatment_type) and ZERO rows where treatment_type is "Death" or "HL Diagnosis".
result: [pending]

### 2. Collapse accuracy spot-check
expected: For one patient with multiple episodes of the same treatment_type, the collapsed row's `episode_start` = the earliest of that patient's episode_start values for that type and `episode_stop` = the latest episode_stop; multi-value fields (cancer_category, drug_names, episode_dx_categories, etc.) are the deduped, sorted, semicolon-joined union of the merged episodes.
result: [pending]

### 3. R/88 Section 15n full pass
expected: On HiPerGator with real data, R/88 Section 15n's 14 structural checks all report PASS (locally they pass in isolation; full R/88 run requires production data — same as Phase 116 Section 15m).
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
