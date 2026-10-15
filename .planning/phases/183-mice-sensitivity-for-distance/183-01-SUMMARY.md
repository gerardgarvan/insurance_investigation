---
plan: "183-01"
phase: "183-mice-sensitivity-for-distance"
status: checkpoint
checkpoint_type: human-action
---

# 183-01 SUMMARY: Setup, Inputs, Patient Dataset, Reproduction Gate

## Task 0 Names

All column names and labels recorded from the writing scripts (not guesses).
No code changes in this task.

### 1. Phase 179 RDS columns
**Source:** `R/179_cbc_patient_year.R` lines 309-310 (final `dplyr::select`)

| Constant | Column name | Notes |
|----------|-------------|-------|
| `COL_ID` | `ID` | patient identifier |
| `COL_YEAR_INDEX` | `year_index` | integer year number |
| `COL_YEAR_START` | `year_start` | Date; anchor + 365*(year_index-1) |
| `COL_YEAR_END` | `year_end` | Date; anchor + 365*year_index |
| `COL_CBC_YEAR` | `cbc_year` | 0/1 outcome |
| `COL_MEDIAN_DIST` | `median_distance` | patient-level median distance mi |
| `COL_FAR` | `far` | 0/1/NA |
| `COL_EXP_MISSING` | `exposure_missing` | logical |
| `COL_TRIAGE` | `triage` | character; "not in R/121" if absent |

Also present: `cbc_year_broad`, `far_year_median`, `year_index_cat` (derived).

### 2. R/179 `run_gee()` function
**Source:** `R/179_cbc_patient_year.R` lines 398–434

Copied verbatim into R/183 SECTION 0 with comment "copied verbatim from R/179 lines 398-434; do not edit".
Signature: `run_gee(data, outcome, exposure, label)`
Key internals: `arrange(ID, year_index)`, `droplevels(year_index_cat)`, `geepack::geeglm(y ~ x + year_index_cat, id=cl, family=binomial("logit"), corstr=GEE_CORSTR)`, robust `Std.err`, returns list with `or`, `ci_lo`, `ci_hi`.

Also copied verbatim: `sup()` (lines 81–85), `show_rate()` (lines 86–89), `crude_or()` (lines 90–93), `as_id()` (line 94).

### 3. R/122 RDS columns
**Source:** `R/122_encounter_distance.R` lines 685–707 (`dplyr::select`)

| Constant | Column name |
|----------|-------------|
| `COL_122_ID` | `ID` |
| `COL_122_ADMIT_DATE` | `ADMIT_DATE` |
| `COL_122_ZIP5_PAT` | `zip5_patient` |
| `COL_122_ZIP5_FAC` | `zip5_facility` |
| `COL_122_SOURCE` | `SOURCE` |
| `COL_122_DIST_STATUS` | `distance_status` |

### 4. R/169 RDS
**Source:** `R/169_single_source_care.R` lines 44–86, 263–266

- Path pattern: `output/internal/single_source_care_<YYYYMMDD>.rds`
- Pinned default: `output/internal/single_source_care_20261008.rds`
- `COL_169_ID`: `ID`
- `COL_169_SSC_POST`: `single_source_care_post` — integer 0/1/NA

### 5. ADI CSV
**Source:** `data/reference/zip5_adi_summary.csv` (header confirmed by `git show HEAD:...`):

```
ZIP5,adi_natrank_median,adi_natrank_p25,adi_natrank_p75,...
```

- `COL_ADI_ZIP5`: `ZIP5`
- `COL_ADI_VALUE`: `adi_natrank_median`

### 6. Demographics and payer
**Demographics (age_at_anchor, sex):** Read from DuckDB `DEMOGRAPHIC` table (columns `ID`, `BIRTH_DATE`, `SEX`). No pre-existing patient-level age_at_anchor RDS exists without new derivation; computed inline as `difftime(anchor, BIRTH_DATE, units="days") / 365.25`.

**Payer:** `payer_summary RDS` in `output/` dir, column `PAYER_CATEGORY_PRIMARY` — same source as `R/165_distance_cbc_association.R` lines 156–170. If RDS absent → dropped with reason logged (D-07b).

### 7. utils_address.R helpers
**Source:** `R/utils/utils_address.R`

- Gazetteer loader: `.load_zcta_gazetteer()` (internal), called via `get_zip_centroid()` (line 832)
- Haversine helper: `haversine_km(lat1, lon1, lat2, lon2)` (line 93) — **returns km**
- Miles conversion: multiply by 0.621371 (confirmed from R/122 line 399)
- Centroid columns used: `INTPTLAT` and `INTPTLONG` (or `INTPTLON` if latter absent) per line 724–726

### 8. Phase 179 workbook
**Source:** `R/180_cbc_missing_capture.R` lines 236, 248

- Sheet: `Model_Results`
- Exact label for primary: `"Primary: years 2+"` → constant `LBL_P179_PRIMARY`
- "Secondary: all years" label existence: checked at runtime; constant `LBL_P179_SECONDARY`
- Reader used in R/180: `openxlsx::read.xlsx(path, sheet = "Model_Results")` (line 248); columns `Analysis`, `OR`, `CI_lo`, `CI_hi`

### 9. Phase 180 KEY labels
**Source:** `R/182_facility_zip_recovery_report.R` lines 242–243

- `LBL_P180_FAR1`: `"MISS-02 (missing -> far=1)"` (sheet `KEY`, Field column)
- `LBL_P180_FAR0`: `"MISS-03 (missing -> far=0)"` (sheet `KEY`, Field column)
- Reader from R/182 lines 232–240: `openxlsx::read.xlsx(path, sheet="KEY")`, then match `Field == label`

### 10. xlsx package
**Source:** `R/180_cbc_missing_capture.R` line 43

- Package: `openxlsx`

---

## Checkpoint: HiPerGator Run Required

**Plan 01 complete.** The script `R/183_mice_sensitivity_distance.R` now contains SECTIONS 0–3 and stops with:
```
==== R/183 Plan 01 complete: stopped after reproduction gate ====
```

### To run:
```r
# repo root; git pull; module load R/4.5; R
source("R/183_mice_sensitivity_distance.R", local = new.env(parent = globalenv()))
```

### Paste back:
- Pinned paths (the six `{var}: {path} (pinned=...)` lines)
- Patient / py / missing counts (`n_patients`, `n_py`, `n_missing`)
- Availability table (printed to console)
- DROPPED list (if any variables were dropped)
- Task-0 line (`Task-0 PASS ...` or error message)

**Resume signal:** "approved" (if Task-0 PASS) or paste the error.

---

## Self-Check

- [x] Task 0 names table lists all ten items with file:line refs
- [x] R/183 created with SECTIONS 0–3
- [x] `grep: R183_R169_RDS, R183_ADI_CSV` — ✓ (PINS list)
- [x] `grep: log1p(` — ✓ (pat_exposure mutate)
- [x] `grep: prop_cbc_years = mean(cbc_year)` — ✓ (pat_outcome)
- [x] `exposure_missing` absent from pat_outcome pipeline — ✓
- [x] `dist_to_source_facility_mi` ≥ 3 occurrences — ✓
- [x] `post_anchor_enc_count` with no `distance_status` filter in that block — ✓
- [x] `miss_reason` absent from predictor vector — ✓ (excluded from `avail_vars`)
- [x] `copied verbatim from R/179` comment — ✓
- [x] no `mice(` call — ✓
- [x] no `Rscript` — ✓
