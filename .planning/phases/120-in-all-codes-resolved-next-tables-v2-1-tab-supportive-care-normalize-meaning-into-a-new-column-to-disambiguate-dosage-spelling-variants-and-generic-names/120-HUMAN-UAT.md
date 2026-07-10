---
status: partial
phase: 120-in-all-codes-resolved-next-tables-v2-1-tab-supportive-care-normalize-meaning-into-a-new-column-to-disambiguate-dosage-spelling-variants-and-generic-names
source: [120-VERIFICATION.md]
started: 2026-07-10T00:00:00Z
updated: 2026-07-10T00:00:00Z
---

## Current Test

[awaiting human testing on an R-capable host with internet]

## Tests

### 1. Run R/105 on an R-capable box with internet (login node or local R + internet, NOT a compute node)
command: Rscript R/105_normalize_supportive_care_meaning.R
expected: Exits 0; prints norm_source breakdown + "round-trip verify: PASSED"; creates data/reference/rxnorm_ingredient_cache.csv (cols rxcui, ingredient_name, source, resolved_at); mutates data/reference/all_codes_resolved_next_tables_v2.1.xlsx so the Supportive Care tab gains col G "Normalized Meaning" with 171 non-blank values; all 8 sheets preserved in order; other sheets' row counts intact. Spot-check: all ondansetron/Zofran variants → "ondansetron"; dexamethasone phosphate → "dexamethasone". If no internet, still exits 0 via rule-based fallback.
result: [pending]

### 2. Run R/88 smoke test Section 15r (isolate if full run stops on HiPerGator-only sections)
expected: All 14 Phase 120 Section 15r checks report PASS; SMOKE-120-01 summary line printed. parse("R/39_run_all_investigations.R") and parse("R/88_smoke_test_comprehensive.R") both succeed.
result: [pending]

### 3. Confirm downstream reader R/55 still parses the Supportive Care tab after the col-G write
expected: R/55 reads Code + Meaning columns unaffected by the trailing "Normalized Meaning" col G (the "meaning" str_detect match still resolves to position 2).
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
