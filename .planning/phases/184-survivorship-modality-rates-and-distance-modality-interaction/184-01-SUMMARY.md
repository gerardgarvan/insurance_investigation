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
  - "Eligibility frame: all CC patients × unrestricted modalities; Mammogram/Breast MRI restricted to DEMOGRAPHIC.SEX='F' via duck_query() (open-query-disconnect pattern)"
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

**Source:** `R/147_surveillance_modality_frequency.R` (line 538) and confirmed from events RDS at runtime (2026-10-16 run: 14 modalities, 1,054,151 rows, 8,623 patients).

**CBC label in events RDS:** `"Complete blood count"` — set as `LBL_CBC` constant (reference level per D-08). Guard added: stop with all found modality labels if LBL_CBC is not in mod_labels.

### 5. CBC event definition — R/147/R/166 vs Phase 165/179

**Phase 165/179 (build_cbc_events):** WBC (6690-2) + Hgb (718-7) + PLT (777-3) resulted the same calendar date (`R/179` line 70, `R/165` line 14, `R/88` line 6455).

**R/147/R/166 (build_dated_post_events):** uses the surveillance codeset primary-tier events; the CBC codeset row uses the `component` match type (`build_component_events()`), which implements WBC + Hgb + PLT same-day — same definition as Phase 165/179.

**D-22 note in R/147 (line 538):** "WBC 6690-2 + Hgb 718-7 + PLT 777-3 resulted the same day = one CBC event; sensitivity tier only" — this refers to the fallback sensitivity tier; primary tier uses the same three-LOINC rule.

**Status:** The definitions should be the same. D-16a check at runtime will confirm or stop with the agreement table.

### 6. Eligibility

**Source:** `R/147` via `modality_eligible_sex()` (`R/utils/utils_surveillance.R` lines 254–258), reading the `eligible_sex` attribute set by `load_modality_lookup()` from the Modalities sheet (`data/reference/README.md` line 285).

**Type:** Patient-level (not time-varying). No treatment-dependent or time-dependent eligibility applies to any modality in the standard surveillance frequency table. `echo_post_anthracycline` (`R/utils/utils_anthracycline_echo.R` line 304) is a separate R/166 Plan 03 output and does not appear in `survivorship_dated_events`.

**Values:**
- `""` (blank) = all patients eligible — applies to all modalities except Mammogram and Breast MRI.
- `"F"` = female only — Mammogram and Breast MRI (`data/reference/README.md` line 285; `R/147` line 83).
- `"M"` = male only — none currently.

**Eligibility RDS:** None. `R/147` saves `surveillance_modality_patient_<date>.rds` (`build_patient_modality`, `R/utils/utils_surveillance.R` line 610) — one row per ID × modality for patients who HAD events; this is an events summary, not a denominator eligibility frame. `R/166` saves events RDS and rates-parts RDS, also events-based. No prebuilt eligibility file exists; derivation is done inline in R/184.

**DuckDB connection:** `duck_query()` helper (open-query-disconnect in one call) used for DEMOGRAPHIC.SEX lookup. Copied from `R/147` lines 283–290 (demo_tbl pattern). Never hold `pcornet_con` open across pipeline helpers.

**R/184 implementation:**
- Unrestricted modalities: `tidyr::expand_grid(ID = cc_patient_ids, modality = unrestricted_labels)`
- Sex-restricted (Mammogram, Breast MRI): `tidyr::expand_grid(ID = female_ids, modality = sex_restricted_labels)`
- Sanity check: eligible N per modality must equal `n_cc_patients` (unrestricted) or `n_female_ids` (sex-restricted); stops with both numbers if mismatch.

**R/166 application (for reference):** `build_dated_post_events()` does not apply sex restriction — returns all primary-tier post-anchor events. Sex restriction is applied at stats level in R/147 via `compute_eligible_modality_stats()` (`R/utils/utils_surveillance.R` line 991).

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

**1. [Rule 2 - Fixed] Eligibility sex-restriction applied in Plan 01**

- **Original deviation:** Plan 01 placeholder used all CC patients × all modalities; sex restriction was deferred.
- **Fix (2026-10-16):** `duck_query()` helper added (open-query-disconnect); DEMOGRAPHIC.SEX queried immediately before eligibility build; Mammogram/Breast MRI restricted to females. Sanity check added (stop if eligible N ≠ expected). SUMMARY updated.
- **Impact:** None — gate was already confirmed passing before this fix.

**2. [Observation] `renv.lock` not found locally**

- `MASS` is a recommended package, always present. `sandwich` loaded conditionally with `requireNamespace()` guard and informational message.

**3. [Fixed] build_cbc_events() called before cc_patient_ids defined**

- **Error:** `object 'cc_patient_ids' not found` — the call was placed in section 3a before
  `cc_patient_ids <- unique(py_cc$ID)` was defined in section 3b.
- **Fix (2026-10-16):** Moved the build_cbc_events block to section 3b, immediately after
  `cc_patient_ids` is defined. Copied verbatim from R/179 lines 186-195 with `filter(!is.na(cbc_date))` and
  `distinct()` before transmute. `close_pcornet_con()` called immediately after the call.

**4. [Decided] Eligibility: sex restriction only; no R/166 xlsx comparison**

- **Decision (2026-10-16):** R/166 `survivorship_modality_rates_long` contains only patients with
  a recorded event — not a denominator frame. Removed `R184_R166_XLSX` pin and the "R/184 eligible N
  exceeds R/166 n_patients" hard stop. Primary eligibility = sex restriction only (D-07).
  Anthracycline echo/MUGA sensitivity deferred to Plan 02 (D-07a).
- **Added:** Event-count construction check (section 3f-iii) replaces the R/166 comparison as
  the hard stop verifying event-count integrity.

## Known Stubs

Anthracycline echo/MUGA sensitivity (D-07a) deferred to Plan 02.

## Self-Check: PENDING

(Self-check will run after HiPerGator confirmation in Plan 02 close-out.)
