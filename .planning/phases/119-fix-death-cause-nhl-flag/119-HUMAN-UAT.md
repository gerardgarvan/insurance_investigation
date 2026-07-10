---
status: partial
phase: 119-fix-death-cause-nhl-flag
source: [119-VERIFICATION.md]
started: 2026-07-09T00:00:00Z
updated: 2026-07-09T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Rebuild DuckDB then run R/102 and inspect output/death_cause_nhl_flag.csv
expected: cause_of_death_is_nhl column has non-zero TRUE and/or FALSE values (not 100% blank); R/102 console reports non-zero TRUE/FALSE tallies
result: [pending]

### 2. Run R/103_death_cause_diagnostic.R
expected: Console prints per-source non-null counts + deceased-set coverage + classify_codes NHL matches for DEATH_CAUSE / TR1.CAUSE_OF_DEATH / TR2-3.DCAUSE, plus a single RECOMMENDATION line; writes output/diagnostics/death_cause_source_inventory.csv
result: [pending]

### 3. Run R/01 (force_reload=TRUE) then R/03, then get_pcornet_table("DEATH_CAUSE") %>% collect() %>% nrow()
expected: Returns > 0 rows; DuckDB now contains 16 tables so R/88 IS_LOCAL count check passes
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
