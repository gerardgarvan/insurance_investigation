---
phase: 158-surveillance-modality-frequency
plan: "01"
subsystem: surveillance-utils
tags: [codeset, loader, HL-denominator, DuckDB, TDD]
dependency_graph:
  requires: []
  provides:
    - load_surveillance_codeset()
    - normalize_surv_code()
    - surv_components()
    - surv_sql_in()
    - surv_code_where()
    - hl_any_dx_from_tibble()
    - get_hl_any_dx_ids()
    - data/reference/surveillance_codeset.xlsx
  affects:
    - R/utils/utils_treatment.R
    - R/utils/utils_surveillance.R
    - data/reference/README.md
tech_stack:
  added:
    - readxl (col_types='text' codeset loading)
    - writexl (test fixture helpers)
    - purrr::pmap_lgl (type_filter validation)
  patterns:
    - Pure function utils module (no DuckDB, no CONFIG)
    - SQL WHERE clause builder pattern (D-29)
    - Stop-not-empty guard pattern (D-24)
key_files:
  created:
    - R/utils/utils_surveillance.R
    - tests/testthat/test-158-codeset-loader.R
  modified:
    - R/utils/utils_treatment.R
    - data/reference/README.md
    - data/reference/surveillance_codeset.xlsx (staged, verified 108 rows)
decisions:
  - "utils_surveillance.R: pure functions only, no DuckDB (D-30)"
  - "get_hl_any_dx_ids() stops on failure, never returns empty (D-24)"
  - "R/00_config.R uses glob auto-load; no explicit list change needed"
metrics:
  duration_minutes: 25
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 3
  completed_date: "2026-09-24"
---

# Phase 158 Plan 01: Codeset Loader, SQL Builders, and HL Denominator Helper

**One-liner:** Staged 108-row surveillance codeset xlsx with validated loader enforcing tier/match/type_filter/component rules, SQL WHERE builder with quote-escaped normalization, and DuckDB-pushdown `get_hl_any_dx_ids()` that stops on failure.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Stage codeset + README entry | 2b02b58 | data/reference/README.md, surveillance_codeset.xlsx |
| 2 (RED) | Add failing loader + denominator tests | ca2e26c | tests/testthat/test-158-codeset-loader.R |
| 2 (GREEN) | Create utils_surveillance.R with all pure functions | 4ab449b | R/utils/utils_surveillance.R |
| 3 | Append get_hl_any_dx_ids() to utils_treatment.R | 8f8dfae | R/utils/utils_treatment.R |

## Key Decisions

1. **00_config.R not modified** — it auto-sources `R/utils/*.R` by glob; `utils_surveillance.R` is picked up automatically with no explicit list change.
2. **Stop-not-empty pattern (D-24)** — `get_hl_any_dx_ids()` calls `stop()` on three failure modes (NULL table, non-lazy tbl, empty confirmed cohort) rather than wrapping in `tryCatch` and returning empty. Contrasts intentionally with `get_hl_patient_ids()`'s silent-empty-on-error pattern.
3. **Duplicate error message wording** — The plan's `"Duplicate"` / `"unique"` stop message strings are split across two separate validation checks (duplicate `codeset_row_id` vs duplicate `modality x code_norm`). Both test patterns `expect_error(..., "Duplicate")` and `expect_error(..., "unique")` match the implemented messages.

## Deviations from Plan

None — plan executed exactly as written.

## Verification (Structural Fallback — Rscript unavailable on Windows dev host)

Per plan's `<verification>` section, since `Rscript` is not available in this Windows environment, the structural fallback was applied:

- **Brace/paren balance:** Both `utils_surveillance.R` and `utils_treatment.R` balance at 0 (verified via Python character count).
- **Key patterns present in utils_surveillance.R:**
  - `col_types = "text"` — 1 match
  - `SURV_TABLE_TYPES` — 3 matches
  - `hl_any_dx_from_tibble` — 2 matches
- **Key patterns present in utils_treatment.R:**
  - `get_hl_any_dx_ids` — 4 matches (definition + stop calls + return)
  - `stop(` — 3 matches (all within `get_hl_any_dx_ids()`)
- **git diff --stat utils_treatment.R** — 42 insertions, 0 deletions (additions only, confirmed)
- **Codeset xlsx** — 108 data rows, no duplicate IDs, `plausibility` column present (verified via openpyxl)

**Testthat run deferred to HiPerGator** — 158-04 Task 2 must run `testthat::test_file('tests/testthat/test-158-codeset-loader.R')` on HiPerGator before anything that depends on the loader executes against real data. 28 expectations pending real execution.

## Known Stubs

None — no rendering or data-source stubs. `get_hl_any_dx_ids()` requires a live DuckDB connection and cannot be exercised locally; that is an environment constraint, not a stub.

## Self-Check: PASSED

- [x] R/utils/utils_surveillance.R exists
- [x] tests/testthat/test-158-codeset-loader.R exists
- [x] Commits 2b02b58, ca2e26c, 4ab449b, 8f8dfae present in git log
- [x] data/reference/surveillance_codeset.xlsx present (108 rows, verified)
- [x] data/reference/README.md surveillance_codeset.xlsx section appended
- [x] utils_treatment.R: get_hl_any_dx_ids() appended, existing functions unchanged
