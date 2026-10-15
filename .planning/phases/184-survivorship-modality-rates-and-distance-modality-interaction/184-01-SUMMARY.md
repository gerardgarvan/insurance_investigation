---
phase: 184-survivorship-modality-rates-and-distance-modality-interaction
plan: "01"
subsystem: modality-rates
tags: [gee, poisson, modality, survivorship, phase-184]
dependency_graph:
  requires: [R/179_cbc_patient_year.R, R/166_survivorship_modality_rates.R, R/147_surveillance_modality_frequency.R]
  provides: [R/184_modality_rate_model.R SECTIONS 0-3, output/internal/modality_long_<date>.rds]
  affects: [184-02-PLAN.md]
tech_stack:
  added: []
  patterns: [pin() from R/183, run_gee() verbatim from R/179, exact-label reader from R/183, year_index_cat from R/179]
key_files:
  created: [R/184_modality_rate_model.R]
  modified: []
decisions:
  - "MODR_CORSTR='independence' (D-04); P179_CORSTR from CONFIG$distance_gee_corstr (gate only)"
  - "Eligibility frame = all Phase 179 CC patients × all modalities; sex restriction deferred to Plan 02 (DEMOGRAPHIC read)"
  - "Events source = R/166 survivorship_dated_events RDS via R/147 pointer run_date"
metrics:
  duration: "~30 min"
  completed: "2026-10-15"
  tasks: 3
  files: 1
---

# Phase 184 Plan 01: Modality Rate Model — Sections 0-3 Summary

**One-liner:** R/184 SECTIONS 0-3 written: constants/helpers verbatim from R/179, R/183 pin/exact-label patterns, Phase 179 reproduction gate, and long patient × modality × year frame with D-16a/b CBC checks.

## Task 0 Names

### 1. Phase 179 RDS columns and `run_gee()` / `year_index_cat`

**Source:** `R/179_cbc_patient_year.R`

**RDS final select (line 309-310):**
```
ID, year_index, year_start, year_end, cbc_year, cbc_year_broad,
median_distance, far, far_year_median, exposure_missing, triage
```

**`run_gee()` (lines 398-434):** function(data, outcome, exposure, label); uses global `GEE_CORSTR`; `geepack::geeglm(y ~ x + year_index_cat, family=binomial("logit"), corstr=GEE_CORSTR, id=cl)`; robust SE from `cf["x","Std.err"]`; fallback to crude OR on GEE error.

**`year_index_cat` (line 333):**
```r
factor(if_else(year_index >= 5L, "5+", as.character(year_index)),
       levels = c("1","2","3","4","5+"))
```

### 2. R/183 exact-label reader (copy target)

**Source:** `R/183_mice_sensitivity_distance.R` lines 548-562

**Pattern:** `openxlsx::read.xlsx(path, sheet="Model_Results")`; check `"Analysis"` column; `sheet_df[trimws(as.character(sheet_df$Analysis)) == label, ]`; require exactly 1 matching row; return `list(or=..., ci_lo=..., ci_hi=...)` reading columns `OR`, `CI_lo`, `CI_hi`.

### 3. Dated modality event source

**Source:** `R/166_survivorship_modality_rates.R` lines 236-244

**RDS:** `output/internal/survivorship_dated_events_<run_date>.rds`

**Path pattern:** `file.path(CONFIG$cache$outputs_dir, glue("survivorship_dated_events_{run_date}.rds"))`

**Columns:** `ID, modality, event_date` (from `build_dated_post_events()` in `utils_surveillance_rates.R` line 48-53: primary-tier, post-anchor, type_ok, distinct triples)

**Dated file to pin:** `R184_EVENTS_RDS` — no fixed date; derived from R/147 pointer `run_date` key (`output/logs/147_verify_last_pass.txt`).

### 4. Modality labels exactly as stored (including CBC label)

**Source:** `R/147_surveillance_modality_frequency.R` (line 538) and old R/12/R/14 scripts; confirmed in events_rds at runtime.

**Known modalities:** `CBC`, `MAMMOGRAM`, `BREAST_MRI`, `ECHO`, `STRESS_TEST`, `ECG`, `MUGA`, `PFT`, `TSH`, `BMP`, `CMP`, `LIPID`, `LFT`, `KIDNEY` (from `surveillance_codeset.xlsx` Modalities sheet, column `modality`).

**CBC label:** `"CBC"` — set as `LBL_CBC` constant (reference level per D-08).

### 5. CBC event definition — R/147/R/166 vs Phase 165/179

**Phase 165/179 (build_cbc_events):** WBC (6690-2) + Hgb (718-7) + PLT (777-3) resulted the same calendar date (`R/179` line 70, `R/165` line 14, `R/88` line 6455).

**R/147/R/166 (build_dated_post_events):** uses the surveillance codeset primary-tier events; the CBC codeset row uses the `component` match type (`build_component_events()`), which implements WBC + Hgb + PLT same-day — same definition as Phase 165/179.

**D-22 note in R/147 (line 538):** "WBC 6690-2 + Hgb 718-7 + PLT 777-3 resulted the same day = one CBC event; sensitivity tier only" — this refers to the fallback sensitivity tier; primary tier uses the same three-LOINC rule.

**Status:** The definitions should be the same. D-16a check at runtime will confirm or stop with the agreement table.

### 6. Eligibility

**Source:** `R/147` via `modality_eligible_sex()` (`utils_surveillance.R` line 256-258), reading attribute `eligible_sex` from `load_modality_lookup()`.

**Type:** Patient-level (not time-varying).

**Values:** `""` = all patients eligible; `"F"` = female only (Mammogram, Breast MRI); `"M"` = male only (none currently).

**R/166 application:** `build_dated_post_events()` does not apply sex restriction — it returns all primary-tier post-anchor events. Sex restriction is applied at the stats level in R/147 via `compute_eligible_modality_stats()`.

**R/184 approach (Plan 01):** Eligibility frame uses all Phase 179 complete-case patients for all modalities (matching D-07 intent); sex restriction for Mammogram/Breast MRI added in Plan 02 via DuckDB DEMOGRAPHIC query.

### 7. `sandwich` and `MASS` in renv.lock

`renv.lock` not found locally (lives on HiPerGator). `MASS` is a base R recommended package always present. `sandwich`: loaded conditionally in R/184 with `requireNamespace("sandwich", quietly=TRUE)` — if absent, NB sensitivity SEs unavailable and a NOTE is printed. Install interactively + `renv::snapshot()` at checkpoint if needed (D-24).

### 8. R/147 pointer file keys used by R/166

**Source:** `R/166_survivorship_modality_rates.R` lines 68-83

**File:** `output/logs/147_verify_last_pass.txt`

**Keys read by R/166:**
- `run_date` → used to build `surveillance_modality_patient_<run_date>.rds` path
- `log` → checked that `readLines(log)` contains `"OVERALL: PASS"`

**Keys read by R/179 (lines 104-119):**
- `rds_path` (primary), `rds` (fallback), `run_date` (fallback for path construction)

**R/184 uses both patterns:** tries `rds_path`, then `rds`, then constructs from `run_date` (R/179 pattern). Also reads `run_date` to construct the `survivorship_dated_events_<run_date>.rds` path (R/166 pattern).

---

## Tasks Executed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 0 | Record names (read-only) | N/A (no code) | — |
| 1 | SECTIONS 0-2 (setup, pins, gate) | 0f22f49 | R/184_modality_rate_model.R |
| 2 | SECTION 3 (long frame + CBC check) | 0f22f49 | R/184_modality_rate_model.R |
| 3 | HiPerGator run to checkpoint | — (awaiting) | — |

Tasks 1 and 2 were committed together (single file, sequential sections).

## Deviations from Plan

### Auto-applied adjustments

**1. [Rule 2 - Missing functionality] Eligibility frame deferred sex-restriction**

- **Found during:** Task 2 implementation
- **Issue:** Sex restriction for Mammogram/Breast MRI requires DuckDB DEMOGRAPHIC query; no DEMOGRAPHIC access during local script writing; Plan 01 scope is setup through long-frame checkpoint only.
- **Fix:** Plan 01 eligibility frame includes all CC patients for all modalities; Plan 02 will add sex filtering when DuckDB DEMOGRAPHIC is available (same session as the HiPerGator run). A NOTE is printed at runtime.
- **Impact:** Zero-event female patients count in Mammogram/Breast MRI denominator until Plan 02 restriction is applied. Does not affect CBC check (D-16a/b).

**2. [Observation] `renv.lock` not found locally**

- `MASS` is a recommended package, always present. `sandwich` loaded conditionally with `requireNamespace()` guard and informational message.

## Known Stubs

- Eligibility sex-restriction (Mammogram, Breast MRI) is noted in a runtime message but not yet implemented. Plan 02 must complete this before rates and model fitting.

## Self-Check: PENDING

(Self-check will run after HiPerGator confirmation in Plan 02 close-out.)
