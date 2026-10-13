---
phase: 179-cbc-patient-year
plan: "01"
subsystem: analysis
tags: [patient-year, cbc, distance, exposure, rds]
dependency_graph:
  requires: [R/147 output, R/122 output, R/121 output, DuckDB]
  provides: [output/internal/cbc_patient_year_YYYYMMDD.rds]
  affects: [Phase 180 missing-exposure bias check, Plan 179-02 GEE models]
tech_stack:
  added: []
  patterns: [tidyr::uncount patient-year expansion, DuckDB SQL push-down, mtime RDS discovery]
key_files:
  created: [R/179_cbc_patient_year.R]
  modified: []
decisions:
  - "CDM_CUTOFF sourced from EXTRACT_DATE in R/00_config.R (2025-09-15); no fallback date"
  - "Anchor from R/147 surveillance_modality_patient RDS (not get_hl_any_dx_ids())"
  - "DEATH table absence handled gracefully with message; no censoring applied if absent"
metrics:
  duration: "~25 min"
  completed: "2026-10-13"
  tasks: 3
  files: 1
---

# Phase 179 Plan 01: CBC Patient-Year Assembly Summary

**One-liner:** Patient-year table assembled from R/147 anchors with half-open 365-day intervals,
DEATH censoring, primary CBC via `build_cbc_events()`, 15-LOINC broad hematology via SQL push-down,
patient-level median distance exposure with `NA` far when missing, and per-year sensitivity
exposure; validated and written to `output/internal/cbc_patient_year_<date>.rds`.

---

## Pre-flight Findings (Task 1)

### 1. R/147 anchor RDS path and columns

- **File pattern:** `surveillance_modality_patient_<YYYYMMDD>.rds` in `CONFIG$output_dir`
  (`R/147_surveillance_modality_frequency.R` line 697)
- **Key columns:** `ID`, `hl_anchor_date` (derived from `first_hl_dx_date` in the R/47
  confirmed cohort RDS; cast to `Date` on load)
- **R/165 comparison:** R/165 calls `get_hl_any_dx_ids()` (a DuckDB DIAGNOSIS query), not
  the R/147 RDS. Per D-02, R/179 uses the R/147 RDS as its authority. A cross-check against
  `get_hl_any_dx_ids()` is attempted at runtime and any difference in patient counts is logged;
  it does not block execution.

### 2. CDM data cutoff

- **Source:** `EXTRACT_DATE <- "2025-09-15"` at line 85 of `R/00_config.R`. This constant
  records the PCORnet CDM data pull date (Mailhot_V1_20250915) and is the documented end-of-data
  boundary for this project.
- **No `CONFIG$analysis_end_date`, `CONFIG$cdm_cutoff`, or similar key exists** in `R/00_config.R`
  (grep confirmed). `EXTRACT_DATE` is the only documented date constant for this purpose.
- **Decision:** R/179 reads `EXTRACT_DATE` (sourced via `R/00_config.R`), parses it as a `Date`,
  and `stopifnot(!is.na(CDM_CUTOFF))` — no hard-coded fallback.

### 3. enc_distance RDS filename pattern

- Pattern: `^encounter_distance.*\.rds$` in `CONFIG$output_dir`, most recent by `file.mtime()`
  (matches R/165 Section 1a verbatim, lines 80–90 of `R/165_distance_cbc_association.R`)
- Env-override: `R179_R122_RDS` (mirrors R/177's `R177_R122_RDS` pattern)

### 4. R/121 triage column and key

- The R/121 RDS is a **list** with a `$patients` element (confirmed by R/177 line 104:
  `pat121 <- r121$patients`)
- Key column: `PATID` (not `ID`); renamed to `ID` for joining (R/177 lines 293–295)
- Triage column: `triage` (character)
- Missing match: `coalesce(triage, "not in R/121")`

---

## What Was Implemented

### Section 0 — Setup

- `source(here::here("R/00_config.R"))` loads all utils (including `build_cbc_events()`)
- Packages: `dplyr`, `tidyr`, `geepack`, `openxlsx`, `glue`
- `CUTOFF <- CONFIG$far_from_care_cutoff_mi` with `stopifnot(!is.na(), > 0)`
- `GEE_CORSTR <- CONFIG$distance_gee_corstr` with `stopifnot(nzchar())`
- `CDM_CUTOFF <- as.Date(EXTRACT_DATE)` with `stopifnot(!is.na(CDM_CUTOFF))` — no fallback
- `BROAD_LOINCS` vector (15 LOINCs per D-06)
- `KEY_META` list recording all pinned sources, cutoff date, and parameters

### Section 1 — Inputs

- **1a** R/147 anchor RDS: most-recent `surveillance_modality_patient_*.rds`; distinct
  `(ID, hl_anchor_date)`; cross-check against `get_hl_any_dx_ids()` with tryCatch (non-blocking)
- **1b** enc_distance: env-override (`R179_R122_RDS`) or most-recent `encounter_distance_*.rds`
- **1c** R/121 triage: env-override (`R179_R121_RDS`) or most-recent `zip_problem_inventory_*.rds`;
  graceful warning if absent; `$patients` list element; PATID → ID rename
- **1d** DuckDB connection via `open_pcornet_con()`
- **1e** `cbc_events <- build_cbc_events(pcornet_con, cohort_ids)` — called as-is, not redefined
- **1f** Broad hematology: `DBI::dbGetQuery()` with SQL push-down on 15 LOINCs, `DISTINCT (ID, lab_date)`
- **1g** DEATH table: SQL MIN(DEATH_DATE) per ID; `tryCatch` with informative message if table absent;
  `death_source` recorded in `KEY_META`
- **1h** `close_pcornet_con()`

### Section 2 — Patient-Year Table

- Filter `!is.na(hl_anchor_date)` (D-03 universe)
- `k_max = floor((CDM_CUTOFF - hl_anchor_date) / 365)`, filter `k_max >= 1`
- `tidyr::uncount(k_max, .id = "year_index")` — no fixed cap (per must-have)
- `year_start = anchor + 365*(year_index - 1)`, `year_end = anchor + 365*year_index`
- Construction guard: `stopifnot(all(year_end <= CDM_CUTOFF))`
- Death censoring: left-join `death_dates`, drop rows where `death_date <= year_end`
- Log: patients with anchor, patients with ≥1 year, patient-years before/after death censoring

### Section 3 — Flags, Validation, RDS

- **3a** `cbc_year`: left-join `cbc_events` via `many-to-many`; date filter `> year_start & <= year_end`; `coalesce(…, 0L)`
- **3b** `cbc_year_broad`: same with `broad_events`
- **3c** `median_distance`: computed post-anchor encounters only (`distance_status == "computed"`, `ADMIT_DATE > hl_anchor_date`); `exposure_missing = is.na(median_distance)`; `far = if_else(exposure_missing, NA_integer_, as.integer(median_distance > CUTOFF))`
- **3d** `far_year_median`: per `(ID, year_index)` median over computed encounters in that year's window; `NA_integer_` if none
- **3e** Triage: left-join `triage_map`; `coalesce(triage, "not in R/121")`
- **3f** Six `stopifnot` validations:
  1. `nrow(py_final) == n_py_after_death` (no join fan-out)
  2. `!anyDuplicated(py_final[, c("ID", "year_index")])` (no duplicate keys)
  3. `all(cbc_year %in% c(0L, 1L))`
  4. `all(cbc_year_broad %in% c(0L, 1L))`
  5. `all(is.na(far[exposure_missing]))` (D-08 invariant)
  6. `all(year_end <= CDM_CUTOFF)` (D-04 invariant)
- **3g** `saveRDS(py_final, file.path(CONFIG$output_dir, "internal", glue("cbc_patient_year_{RUN_DATE}.rds")))`

---

## Deviations from Plan

None. Plan executed exactly as written.

**Note on CDM cutoff discovery:** The plan left the cutoff source to Claude's discretion ("documented
project source; record it in KEY"). `EXTRACT_DATE` in `R/00_config.R` (line 85, with the comment
"Extract date for current PCORnet CDM data pull") is unambiguously the correct constant.
No deviation — this was the expected discovery path.

---

## Verification Grep Output

```
grep -n "build_cbc_events\|hl_anchor_date\|exposure_missing\|far_year_median\|year_index" \
  R/179_cbc_patient_year.R | head -30

19:#   DuckDB: LAB_RESULT_CM (CBC re-derive via build_cbc_events() + broad LOINCs)
31:#   D-03: Universe = ALL cohort patients with known hl_anchor_date
33:#   D-05: Primary CBC via build_cbc_events() as-is (no redefinition)
36:#   D-08: exposure_missing = TRUE when no computed post-anchor encounter
37:#   D-09: far_year_median = per-year median distance; NA if no computed enc in year
38:#   D-17: RDS schema: ID, year_index, year_start, year_end, cbc_year, cbc_year_broad,
39:#         median_distance, far, far_year_median, exposure_missing, triage
55:# build_cbc_events(), suppress_small_vec(), suppress_display(), naive_or_se() available.
130:# Most recent by mtime; columns include ID and hl_anchor_date.
145:# Extract one row per patient with ID and hl_anchor_date
147:  dplyr::distinct(ID, hl_anchor_date) |>
148:  dplyr::mutate(hl_anchor_date = as.Date(hl_anchor_date))
151:n_anchor_na    <- sum(is.na(anchors$hl_anchor_date))
152:message(glue("  Anchors from R/147: {n_anchors} patients; {n_anchor_na} missing hl_anchor_date."))
159:  ids_179     <- unique(anchors$ID[!is.na(anchors$hl_anchor_date)])
160:  ids_165     <- unique(anchors_165$ID[!is.na(anchors_165$hl_anchor_date)])
241:# --- 1e. Primary CBC events via build_cbc_events() (D-05) ----------------------
243:message("  Building CBC events (whole record) via build_cbc_events() ...")
245:cbc_events <- build_cbc_events(pcornet_con, cohort_ids)
334:  dplyr::filter(!is.na(hl_anchor_date))
337:message(glue("  Patients with known hl_anchor_date: {n_with_anchor}"))
345:    k_max = as.integer(floor(as.numeric(CDM_CUTOFF - hl_anchor_date) / 365))
355:# year_index = k (1 to k_max); year_start = anchor + 365*(k-1); year_end = anchor + 365*k.
358:  tidyr::uncount(k_max, .id = "year_index") |>
360:    year_start = hl_anchor_date + 365L * (year_index - 1L),
361:    year_end   = hl_anchor_date + 365L * year_index
398:py_keys <- py |> dplyr::select(ID, year_index, year_start, year_end)
405:  dplyr::group_by(ID, year_index) |>
409:  dplyr::left_join(cbc_flag, by = c("ID", "year_index")) |>
416:  dplyr::group_by(ID, year_index) |>
```

```
grep -n "stopifnot\|cbc_patient_year.*rds" R/179_cbc_patient_year.R | head -10

24:#   output/internal/cbc_patient_year_<YYYYMMDD>.rds  (one row per patient-year; D-17)
76:stopifnot(
82:stopifnot(
91:stopifnot(
96:stopifnot(
368:stopifnot(
500:stopifnot(
506:stopifnot(
512:stopifnot(
520:stopifnot(
```

```
grep -n "saveRDS\|cbc_patient_year.*rds" R/179_cbc_patient_year.R | head -5

24:#   output/internal/cbc_patient_year_<YYYYMMDD>.rds  (one row per patient-year; D-17)
548:rds_out <- file.path(internal_dir, glue("cbc_patient_year_{RUN_DATE}.rds"))
549:saveRDS(py_final, rds_out)
```

RDS path is `output/internal/cbc_patient_year_{RUN_DATE}.rds` — under `internal/` as required.

---

## Must-Haves Sign-Off

| Must-have | Status |
|-----------|--------|
| Cohort and hl_anchor_date from R/147 anchor RDS; cohort difference with Phase 165 logged | SATISFIED — Section 1a loads from `surveillance_modality_patient_*.rds`; cross-check against `get_hl_any_dx_ids()` via tryCatch, counts logged |
| CDM cutoff from documented project source; script stops if none found | SATISFIED — `EXTRACT_DATE` from `R/00_config.R` line 85; `stopifnot(!is.na(CDM_CUTOFF))` with no fallback date |
| Patient-years generated per patient up to last fully observed year (no fixed cap); death censoring applied | SATISFIED — `tidyr::uncount(k_max)` where `k_max = floor((CDM_CUTOFF - anchor)/365)`; DEATH table censoring in Section 2 |
| Every patient-year appears in RDS, including years with no encounters or CBCs | SATISFIED — joins use `left_join` + `coalesce(…, 0L)` for CBC flags; no inner join on encounter presence |
| `far` is NA when `exposure_missing` is TRUE | SATISFIED — `dplyr::if_else(exposure_missing, NA_integer_, ...)` in Section 3c; enforced by `stopifnot` |
| Local checks grep only; run is interactive R on HiPerGator | SATISFIED — no `Rscript`, no SLURM; usage line specifies `source(...)` with `local = new.env(...)` |

---

## Known Stubs

None. All columns are wired to real data sources or documented as runtime-dependent (triage = "not in R/121"
for unmatched patients is the correct sentinel, not a stub).

## Self-Check: PASSED

- `R/179_cbc_patient_year.R` exists and was committed at `219b000`
- All six required elements confirmed present by grep output above
- No hard-coded fallback date for CDM_CUTOFF
- `build_cbc_events(` appears once (line 245); no `cbc_loincs <-` redefinition
- RDS output path contains `internal` subdirectory
