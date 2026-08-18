---
phase: 147-read-address-zip5-retract-downstream-artefacts
plan: 02
status: completed
completed: 2026-08-18
---

# Plan 2 Summary — Code Fix Complete

## What was done

**Task 1 — `R/utils/utils_address.R` (three edits):**

1. **Multi-column guard** (replaces single-column ID guard): checks ID, ADDRESS_ZIP5,
   ADDRESS_ZIP9, ADDRESS_PERIOD_START, ADDRESS_PERIOD_END. Error message names "Phase 148"
   and explains the ~47% coverage loss risk.

2. **Incorrect comment removed + coalesce fixed** (mutate block, ~line 165):
   Old: `coalesce(normalize_zip5(zip9_norm), normalize_zip5_raw(ADDRESS_ZIP9))`
   New: `dplyr::coalesce(normalize_zip5(ADDRESS_ZIP5), normalize_zip5(zip9_norm))`
   Comment now references 147-DISCOVERY.md §4 (D-02) and §3 (12 disagreement rows).

3. **Branch C console message corrected** (approximate_zip9()): removed the wrong
   "sentinel-nulled" cause; now says "after coalescing ADDRESS_ZIP5 and ADDRESS_ZIP9 prefix".

**Task 2 — Fixture + tests:**

- `tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv`: rewritten from 1 row / 3 columns to
  4 rows / 5 columns, covering all 2×2 cells (yes/yes, yes/no, no/yes, no/no).
- `tests/testthat/test-utils-address.R`: 4 new tests appended (6 total), one per 2×2 cell.
  The ZIP5-only test (yes/no cell) directly covers the 18,731 previously-invisible records.

## Verification results

| Check | Expected | Got |
|---|---|---|
| `normalize_zip5(ADDRESS_ZIP5)` in mutate | ≥1 hit | line 168 |
| "No separate ADDRESS_ZIP5 column exists" | 0 | 0 |
| ADDRESS_ZIP5 mentions in file | ≥3 | 8 |
| "Phase 148" mentions | ≥2 | 4 |
| ADDRESS_PERIOD_END mentions | ≥2 | 6 |
| Fixture header has ADDRESS_ZIP5 | yes | yes |
| Fixture data rows | 4 | 4 |
| "ZIP5-only record" in test file | ≥1 | 2 |
| test_that() count | ≥6 | 6 |

## Gate status

Plan 3 (HiPerGator re-run) is unblocked. The fix is in place on the dev box.
Windows parse checks: structural — R/88 requires HiPerGator environment.
