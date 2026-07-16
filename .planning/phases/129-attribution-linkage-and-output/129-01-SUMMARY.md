---
phase: 129-attribution-linkage-and-output
plan: "01"
subsystem: doi-attribution
tags: [duckdb, attribution, linkage, three-state-flag, rituximab, methotrexate, doi]
dependency_graph:
  requires:
    - "128-doi-classification (doi_encounters.rds, doi_patients.rds)"
    - "R/26_treatment_episodes.R (treatment_episode_detail.rds)"
    - "R/00_config.R (RITUXIMAB_CODES, MTX_CODES, DOI_ATTRIBUTION_WINDOW_DAYS, ICD_CODES)"
    - "R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table)"
    - "R/utils/utils_treatment.R (get_hl_patient_ids pattern for DX_TYPE gating)"
  provides:
    - "R/112_doi_attribution_report.R Sections 1-5"
    - "doi_drug_links in-memory frame — drug↔DoI co-occurrence with attribution_method + likely_non_lymphoma_directed"
    - "hl_dx_dated — dated HL diagnosis frame (Plan 02 also uses this)"
  affects:
    - "Plan 129-02 (xlsx sheet assembly + close_pcornet_con)"
    - "Phase 130 (R/39 / SCRIPT_INDEX / R/88 registration targeting R/112)"
tech_stack:
  added: []
  patterns:
    - "Two-tier ENCOUNTERID-equi-join → ±DOI_ATTRIBUTION_WINDOW_DAYS PATID-window linkage (mirrors R/28 D-01/D-02)"
    - "Three-state logical flag via case_when (TRUE/FALSE/NA — NA never coerced to FALSE)"
    - "DuckDB native-filter-before-collect for dated HL-diagnosis pull"
    - "Defensive source() guard: if (!exists('get_hl_patient_ids')) source(utils_treatment.R)"
key_files:
  created:
    - "R/112_doi_attribution_report.R"
  modified: []
decisions:
  - "DuckDB connection teardown deferred to Plan 02 (Plan 01 does not write files; close_pcornet_con() belongs in the xlsx-write plan)"
  - "patient_id renamed to ID on drug_admins so all three frames share the same PATID join key (doi_enc uses ID)"
  - "drug_admins_none rows use doi_category=NA, attribution_method='none' — unified schema for bind_rows without sentinel values"
  - "hl_active_in_window intermediate column dropped via select(-hl_active_in_window) — only the three-state flag is needed downstream"
  - "_for_ prohibition comment rephrased to avoid the literal pattern triggering the acceptance-criteria grep"
metrics:
  duration: "~10 minutes (reconciliation + fix + commit)"
  completed_date: "2026-07-16"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 1
---

# Phase 129 Plan 01: DoI Drug Co-occurrence Attribution Engine Summary

**One-liner:** Two-tier rituximab/MTX↔DoI linkage (ENCOUNTERID equi-join then ±90-day PATID window) with three-state `likely_non_lymphoma_directed` (TRUE/FALSE/NA) driven by a dated HL-diagnosis DuckDB pull.

## What Was Built

`R/112_doi_attribution_report.R` Sections 1–5 — the analytic engine for drug↔DoI co-occurrence attribution.

**Section 1 (Setup):** Library loads (dplyr, glue, stringr, lubridate, janitor), source chain (R/00_config.R, utils_duckdb.R, utils_dates.R), defensive `if (!exists("get_hl_patient_ids"))` guard before sourcing utils_treatment.R, banner message embedding `DOI_ATTRIBUTION_WINDOW_DAYS` via glue.

**Section 2 (Load inputs):** `readRDS` of `doi_encounters.rds`, `doi_patients.rds`, `treatment_episode_detail.rds` (all read-only). Builds flat `rituximab_mtx_codes` vector from `RITUXIMAB_CODES$hcpcs`, `RITUXIMAB_CODES$rxnorm`, `MTX_CODES$hcpcs`, `MTX_CODES$rxnorm`. Filters `tx_detail` to those codes via `triggering_code %in%`, labels `drug_class` (rituximab/methotrexate), renames `patient_id → ID` for a consistent PATID join key.

**Section 3 (Dated HL pull — only new DuckDB query):** Opens DuckDB, mirrors `get_hl_patient_ids()` HL-code filter but retains `DX_DATE` (select ID, DX_DATE). DX_TYPE-gated (`"10"` for ICD-10, `"09"` for ICD-9) against `ICD_CODES$hl_icd10` / `ICD_CODES$hl_icd9`. Native-filtered before `collect()`. Date-parsed via `parse_pcornet_date()`, 1900 sentinels dropped. Connection left open — teardown deferred to Plan 02.

**Section 4 (Two-tier linkage — DOI-ATTR-01):**
- Tier 1: `inner_join` on `ENCOUNTERID` (both sides guarded for `!is.na & != ""`); `attribution_method = "encounter_id"`. `ID = coalesce(ID_drug, ID_dx)` handles the post-join suffix.
- Tier 2: `anti_join` removes tier-1-matched admins, then `inner_join` on `ID` with `filter(abs(as.integer(DX_DATE - treatment_date)) <= DOI_ATTRIBUTION_WINDOW_DAYS)`; `attribution_method = "temporal_window"`. Named constant only — no literal 90.
- Drug admins with no match in either tier: `attribution_method = "none"`, `doi_category = NA`.
- Combined into `doi_drug_links` via `bind_rows`.

**Section 5 (Three-state flag — DOI-ATTR-02):** Computes `hl_active_in_window` per `(ID, treatment_date)` by left-joining matched admins to `hl_dx_dated` and testing `abs(as.integer(DX_DATE - treatment_date)) <= DOI_ATTRIBUTION_WINDOW_DAYS`. Joins back; applies `case_when`:
```r
likely_non_lymphoma_directed = case_when(
  attribution_method == "none"  ~ FALSE,
  hl_active_in_window == TRUE   ~ NA,
  TRUE                          ~ TRUE
)
```
`NA` is preserved as logical — never coerced to FALSE. `hl_active_in_window` helper column dropped after use.

## doi_drug_links Contract (Plan 02 input)

| Column | Type | Values / Notes |
|---|---|---|
| ID | character | PATID join key |
| drug_class | character | "rituximab" / "methotrexate" |
| triggering_code | character | HCPCS or RxNorm CUI |
| treatment_date | Date | drug administration date |
| ENCOUNTERID | character | drug-side ENCOUNTERID |
| drug_name | character | from treatment_episode_detail.rds |
| historical_flag | logical | from treatment_episode_detail.rds |
| doi_code | character | NA for attribution_method == "none" |
| doi_category | character | NA for attribution_method == "none" |
| DX_DATE | Date | DoI encounter date; NA for "none" |
| paraneoplastic_flag | logical | NA for "none" |
| in_hl_cohort | logical | NA for "none" |
| attribution_method | character | "encounter_id" / "temporal_window" / "none" |
| likely_non_lymphoma_directed | logical | TRUE / FALSE / NA (three-state) |

## What Plan 02 Must Do

- Assemble the 4-sheet workbook from `doi_drug_links` (already in-memory).
- Call `close_pcornet_con()` after the xlsx write (connection is still open from Section 3).
- Write `doi_attribution_report.xlsx` to `CONFIG$output_dir`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `_for_` in header comment triggered acceptance-criteria grep**

- **Found during:** Task 2 verification
- **Issue:** Header comment line 12 read `No column carries "_for_" causal language.` — the literal `_for_` pattern caused `grep -c '_for_'` to return 1 instead of 0, failing the DOI-ATTR-03 acceptance criterion.
- **Fix:** Rephrased to `No column uses causal attribution naming.` — preserves the intent without the banned literal pattern.
- **Files modified:** R/112_doi_attribution_report.R (line 12)
- **Commit:** 43ea8c5

### Continuation Reconciliation

The script was already written and staged (Sections 1–5, 362 lines) from a prior interrupted session. This execution:
1. Read the existing file in full.
2. Ran all acceptance criteria checks against both tasks.
3. Found and fixed the `_for_` grep false-positive.
4. Staged the corrected file and committed atomically.

No tasks were re-written; only the one-line comment fix was applied.

## Known Stubs

None. The `doi_drug_links` frame is fully populated at runtime from real data; no hardcoded placeholders. (Structure-only verification on Windows — real row counts confirmed at HiPerGator runtime, Phase 130.)

## Self-Check

Checks run post-summary:
- `R/112_doi_attribution_report.R` exists: FOUND
- Commit 43ea8c5 exists: FOUND
- `_for_` grep count: 0 (PASS)
- `suppress_small` grep count: 0 (PASS)
- Line count: 362 (>= 120, PASS)
- R/111 unmodified: CONFIRMED (not in git diff)

## Self-Check: PASSED
