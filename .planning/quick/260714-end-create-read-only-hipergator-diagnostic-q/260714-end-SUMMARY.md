---
phase: quick-260714-end
plan: 01
subsystem: diagnostics
tags: [med-admin, dispensing, chemo-gap, read-only, diagnostic, hipaa]
dependency_graph:
  requires: [R/00_config.R, R/utils/utils_duckdb.R, R/utils/utils_dates.R, R/utils/utils_treatment.R]
  provides: [output/med_admin_dispensing_gap_diagnostic.csv, console HEADLINE]
  affects: []
tech_stack:
  added: []
  patterns: [self-bootstrap DuckDB, suppress_small HIPAA helper, cohort-scoped + all-patient dual reporting, graceful NULL/column guards]
key_files:
  created:
    - R/107_med_admin_dispensing_gap_diagnostic.R
  modified:
    - R/SCRIPT_INDEX.md
decisions:
  - R/107 is a ONE-OFF sizing diagnostic — NOT wired into R/39 and NOT registered in R/88; SCRIPT_INDEX.md row only
  - MED_ADMIN MEDADMIN_TYPE=='RX' rows carry RxNorm CUIs in MEDADMIN_CODE; matched against TREATMENT_CODES$chemo_rxnorm beyond PRESCRIBING baseline
  - MEDADMIN_TYPE=='ND' volume reported as footprint only (NDC-coded; needs NDC->RxNorm crosswalk not in-repo)
  - DISPENSING: footprint only (rows/patients/dates); explicitly flagged as not chemo-matchable without crosswalk; no fabricated match
  - suppress_small() HIPAA helper suppresses patient counts 1-10 to NA in persisted CSV and console per-group breakdowns
metrics:
  duration: ~15 min
  completed: 2026-07-14
  tasks: 2
  files: 2
---

# Phase quick-260714-end Plan 01: MED_ADMIN/DISPENSING Chemo-Gap Sizing Diagnostic Summary

**One-liner:** Read-only R/107 diagnostic quantifying the silent chemo-detection gap from DISPENSING and MED_ADMIN lacking RXNORM_CUI in the OneFlorida+ extract, sized against the working PRESCRIBING baseline.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write R/107 read-only MED_ADMIN/DISPENSING chemo-gap diagnostic | 859dd67 | R/107_med_admin_dispensing_gap_diagnostic.R (446 lines) |
| 2 | Register R/107 in SCRIPT_INDEX.md (diagnostic row only) | 005cc55 | R/SCRIPT_INDEX.md (row added, counts 7->8, 93->94) |

## What Was Built

### R/107_med_admin_dispensing_gap_diagnostic.R (446 lines)

A standalone read-only diagnostic that sizes the confirmed latent bug in R/26 where DISPENSING and MED_ADMIN contribute zero chemo treatment detection because every R/26 consumer guards on `"RXNORM_CUI" %in% colnames(...)` — a column both tables lack in this extract.

**Sections:**

- **Section 1 (Setup):** `suppressPackageStartupMessages` for dplyr/glue/stringr/lubridate; sources R/00_config.R, utils_duckdb, utils_dates; defensive `get_hl_patient_ids` source if absent.
- **Section 2 (Constants):** `CHEMO_RXNORM <- TREATMENT_CODES$chemo_rxnorm`; output CSV path; `suppress_small()` HIPAA helper (patient counts 1-10 → NA).
- **Section 3 (Self-bootstrap DuckDB):** `USE_DUCKDB <- TRUE; if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()`.
- **Section 4 (Cohort scope):** `get_hl_patient_ids()` with fallback to all-patient if 0 IDs returned.
- **Section 5 (PRESCRIBING baseline):** Guards on NULL table and absent RXNORM_CUI column; filters `RXNORM_CUI %in% CHEMO_RXNORM`, `mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE))`; builds rx_patients, rx_pairs, rx_first_date reference sets for increment calculations.
- **Section 6 (MED_ADMIN incremental):** Guards on NULL table and required columns (MEDADMIN_TYPE, MEDADMIN_CODE, MEDADMIN_START_DATE); RX-coded match via `MEDADMIN_TYPE == "RX" & MEDADMIN_CODE %in% CHEMO_RXNORM`; increment calcs via `setdiff` (new patients) + `anti_join` (new ID+date pairs) + min-date comparison (earlier first-chemo shifts); ND volume separately reported as crosswalk-needed footprint.
- **Section 7 (DISPENSING footprint):** Collects rows/patients/distinct dates; explicit message that chemo match is NOT possible without NDC->RxNorm crosswalk; no fabricated match.
- **Section 8 (HEADLINE + CSV):** Glue-formatted HEADLINE message with HIPAA-suppressed patient counts; `bind_rows` of all available source rows into a tibble; `write.csv(..., row.names = FALSE, na = "")`; `close_pcornet_con()`.

### R/SCRIPT_INDEX.md

- R/107 row added to Post-Renumber Investigations (100+) table after R/106.
- Post-renumber investigations count: **7 → 8**.
- Total script count: **93 → 94**.

## Structural Verification Results (Windows executor)

All 12 structural checks passed:

| Check | Pattern | Result |
|-------|---------|--------|
| 1 | `TREATMENT_CODES$chemo_rxnorm` appears >= 2 times | PASS (11 occurrences) |
| 2a | `MEDADMIN_TYPE == "RX"` present | PASS |
| 2b | `MEDADMIN_CODE %in%` present | PASS |
| 3 | `MEDADMIN_TYPE == "ND"` present | PASS |
| 4 | `coalesce(RX_ORDER_DATE, RX_START_DATE)` present | PASS |
| 5a | `NDC` present | PASS |
| 5b | `crosswalk` present (case-insensitive) | PASS |
| 6 | `get_hl_patient_ids` present | PASS |
| 7 | `suppress` present (HIPAA helper) | PASS |
| 8a | `if (!exists("pcornet_con"` present | PASS |
| 8b | `close_pcornet_con` present | PASS |
| 9 | `HEADLINE:` present | PASS |
| 10a | `write.csv` present | PASS |
| 10b | `na = ""` present | PASS |
| 11 | No `stop(` calls | PASS |
| 12 | Paren/brace balance | PASS (255/255 parens, 18/18 braces) |

## Deviations from Plan

None — plan executed exactly as written.

## Runtime Verification (Deferred to HiPerGator)

This Windows executor has no Rscript and local fixtures lack the real column layout for DISPENSING/MED_ADMIN. The user must confirm the following at runtime on HiPerGator:

1. `Rscript R/107_med_admin_dispensing_gap_diagnostic.R` sources cleanly, bootstraps DuckDB, and completes without `stop()`/crash.
2. PRESCRIBING baseline patient/date counts are non-zero (expected: PRESCRIBING has RXNORM_CUI in this extract).
3. MED_ADMIN RX-coded chemo match returns the increment — new patients, new (ID,date) pairs, earlier-first-date shifts — expected to be substantial (~1.7M RX-coded administrations exist in the extract).
4. The MEDADMIN_TYPE=='ND' volume line prints (crosswalk-needed, unmatched).
5. DISPENSING footprint prints with the explicit "needs NDC->RxNorm crosswalk" flag and no fabricated chemo match.
6. The HEADLINE line prints with filled-in numbers.
7. `output/med_admin_dispensing_gap_diagnostic.csv` is written and no cohort/episode file was changed.
8. Per-group patient counts of 1-10 appear as blank (HIPAA suppression) in the CSV.

## Known Stubs

None. R/107 is a read-only diagnostic — it does not feed into any downstream pipeline output.

## Self-Check: PASSED

- `R/107_med_admin_dispensing_gap_diagnostic.R` — FOUND (446 lines, created this session)
- `R/SCRIPT_INDEX.md` — FOUND, R/107 row present, counts updated
- Task 1 commit `859dd67` — FOUND
- Task 2 commit `005cc55` — FOUND
